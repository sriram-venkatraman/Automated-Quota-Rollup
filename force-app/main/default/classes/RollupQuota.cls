public class RollupQuota implements Queueable {
    private static final Integer MAX_ITERATIONS = 50;
    private static final Integer MAX_DML_ROWS = 10000;
    
    // Run using this command:
    // ID jobID = System.enqueueJob(new RollupQuota());
    // System.Debug('Job: ' + jobID);

    public RollupQuota() {
    }

    // Class to store quoata details with flattened Owner Hierarchy
    // Owner Hierarchy Defined: 
    //      Quota Owner User    <----------Loop until you reach top of chain-----.
    //          > Quota Owner User Role                                          |
    //              > Quota Owner's Parent User Role                             |
    //                  > Quota Owner's Parent User Role - Forecast User --------'
    //                      (this forecast manager assigned for the role)
    class FlattenedQuotas {
        String  ownerHierarchy;
        Decimal amount;
        Decimal quantity;
        String  productFamily;
        Date    startDate;
        String  rawQuotasId;
    }

    public void execute(QueueableContext context) {
        doRollup();
    }

    public void doRollup() {
        Map<String, String> forecastTypes = new Map<String, String>();
        for (ForecastingType ft : [select Id, DeveloperName
                                    from ForecastingType
                                    where IsActive = true]) {
            forecastTypes.put(ft.DeveloperName, ft.Id);
        }
        System.Debug('Forecast Types: ' + forecastTypes);

        Map<Id, UserRole> urList = new Map<Id, UserRole>([select Id,
                                                                 ParentRoleId,
                                                                 ForecastUserId
                                                            from UserRole]);

        // Construct RoleId and it's parent's ForecastUserId
        // Could have avoided following code if we could have had access to ParentRole.ForecastUserId
        Map<String, String> roleManagerUserMap = new Map<String, String>();
        for ( UserRole ur : urList.values() ) {
            if (ur.ParentRoleId != null) {
                roleManagerUserMap.put(ur.Id, urList.get(ur.ParentRoleId).ForecastUserId);
            }
        }

        Map<String, String> userManagerMap = new Map<String, String>();
        Map<String, String> userNameMap = new Map<String, String>();

        // To get User and Manager User Id as defined in the Owner Hierarchy above, let's start with User & Role Id
        // and get Role Id's associated Parent's Forecast User Id; Resultant map contains User Id & Manager Id
        // per definition
        for (User u : [select Id, 
                              UserRoleId,
                              Name
                       from   User
                       where  IsActive = true]){
            if (u.UserRoleId != null && roleManagerUserMap.get(u.UserRoleId) != null) {
                userManagerMap.put(u.Id, roleManagerUserMap.get(u.UserRoleId));
            }
            userNameMap.put(u.Id, u.Name);
        }

        List<FlattenedQuotas> fqs = new List<FlattenedQuotas>();

        // Get all Quota data from the Raw Quota object
        for (Raw_Quotas__c rq : [select Id,
                                        OwnerId,
                                        Start_Date__c,
                                        Amount__c,
                                        Quantity__c,
                                        Product_Family__c
                                from	Raw_Quotas__c
                                where   Is_Active__c = true]) {
            FlattenedQuotas fq = new FlattenedQuotas();
            fq.ownerHierarchy = rq.OwnerId;
            fq.startDate = rq.Start_Date__c;
            fq.amount = rq.Amount__c;
            fq.quantity = rq.Quantity__c;
            fq.productFamily = rq.Product_Family__c;
            fq.rawQuotasId = rq.Id;
            fqs.add(fq);
        }

        System.Debug('Total Raw Quotas: ' + fqs.size());

        Integer currentIteration = 0;
        Integer currentIdx = 0;
        Boolean parentsFound = true;
        Integer parentCount = 0;
        String managerId;

        // Start flattening User-Manager hierarchy chain as Mgr0;Mgr1;Mgr2;Mgr3;User1. Mgr0 is the top of the chain;
        while (currentIteration < MAX_ITERATIONS && parentsFound) {
            if (currentIdx >= fqs.size()) {
                currentIdx = 0;
                parentCount = 0;
                ++currentIteration;
            }

            managerId = userManagerMap.get(fqs[currentIdx].ownerHierarchy.split(';')[0]);

            if (managerId != null) {
                fqs[currentIdx].ownerHierarchy = managerId + ';' + fqs[currentIdx].ownerHierarchy;
                ++parentCount;
            }
            
            if (currentIdx == fqs.size()-1 && parentCount == 0) {
                parentsFound = false;
            }

            ++currentIdx;
        }

        Map<String, Decimal> rolledUpQuotaRevenue = new Map<String, Decimal>();
        Map<String, Decimal> rolledUpQuotaQuantity = new Map<String, Decimal>();
        List<Raw_Quotas__c> rqs2Update = new List<Raw_Quotas__c>();

        // Now break the Owner Hierarchy in to granular user quota, group by User Id, Start Date, Product Family and
        // sum of Amount or sum of Quantity
        // key = UserId,StartDate,ProductFamily
        for (FlattenedQuotas fq : fqs) {
            Raw_Quotas__c rq = new Raw_Quotas__c(Id=fq.rawQuotasId, Owner_Hierarchy__c=null);
            Integer indent = -1;

            for (String o : fq.ownerHierarchy.split(';')) {
                // Build Owner Hierarchy to write back into Raw Quotas.. just a visualization thing
                indent++;
                if (indent == 0) {
                    rq.Owner_Hierarchy__c = '<p>' + userNameMap.get(o) + '</p>';
                }
                else {
                    rq.Owner_Hierarchy__c += '<p class="ql-indent-' + indent + '">⎿' + userNameMap.get(o) + '</p>';
                }

                // Revenue Rollup
                if (fq.amount != null) {
                    if (forecastTypes.get('OpportunityLineItemRevenue') != null) {
                        // Initialize Product level rollup
                        if (rolledUpQuotaRevenue.get(o + ',' + fq.startDate + ',' + fq.productFamily) == null) {
                            rolledUpQuotaRevenue.put(o + ',' + fq.startDate + ',' + fq.productFamily, 0);
                        }
                        // Product level rollup
                        rolledUpQuotaRevenue.put(o + ',' + fq.startDate + ',' + fq.productFamily, 
                                                fq.amount + rolledUpQuotaRevenue.get(o + ',' + fq.startDate + ',' + fq.productFamily));
                    }

                    if (forecastTypes.get('OpportunityRevenue') != null) {
                        // Initialize Opportunity level rollup
                        if (rolledUpQuotaRevenue.get(o + ',' + fq.startDate + ',null') == null) {
                            rolledUpQuotaRevenue.put(o + ',' + fq.startDate + ',null', 0);
                        }

                        // Opportunity level rollup
                        rolledUpQuotaRevenue.put(o + ',' + fq.startDate + ',null', 
                                                fq.amount + rolledUpQuotaRevenue.get(o + ',' + fq.startDate + ',null'));
                    }
                }

                // Quantity Rollup
                if (fq.quantity != null) {
                    if (forecastTypes.get('LineItemQuantityProductDate') != null) {
                        // Initialize Product level rollup
                        if (rolledUpQuotaQuantity.get(o + ',' + fq.startDate + ',' + fq.productFamily) == null) {
                            rolledUpQuotaQuantity.put(o + ',' + fq.startDate + ',' + fq.productFamily, 0);
                        }
                        // Product level rollup
                        rolledUpQuotaQuantity.put(o + ',' + fq.startDate + ',' + fq.productFamily, 
                                                fq.quantity + rolledUpQuotaQuantity.get(o + ',' + fq.startDate + ',' + fq.productFamily));
                    }

                    if (forecastTypes.get('OpportunityQuantity') != null) {
                        // Initialize Opportunity level rollup
                        if (rolledUpQuotaQuantity.get(o + ',' + fq.startDate + ',null') == null) {
                            rolledUpQuotaQuantity.put(o + ',' + fq.startDate + ',null', 0);
                        }

                        // Opportunity level rollup
                        rolledUpQuotaQuantity.put(o + ',' + fq.startDate + ',null', 
                                                fq.quantity + rolledUpQuotaQuantity.get(o + ',' + fq.startDate + ',null'));
                    }
                }
            }
 
            rqs2Update.add(rq);
        }

        System.Debug('Total Rolled Up Amount: ' + rolledUpQuotaRevenue.size());
        System.Debug('Total Rolled Up Quantity: ' + rolledUpQuotaQuantity.size());

        List<ForecastingQuota> fqs2Upsert = new List<ForecastingQuota>();
        if (forecastTypes.get('OpportunityLineItemRevenue') != null ||
            forecastTypes.get('OpportunityRevenue') != null) {
            for (String k : rolledUpQuotaRevenue.keySet()) {
                // key format = UserId,StartDate,ProductFamily
                ForecastingQuota fq = new ForecastingQuota();
                String[] s = k.split(',');
                fq.QuotaOwnerId = s[0];
                fq.StartDate = Date.valueOf(s[1]);
                if (s[2] != 'null') {
                    fq.ProductFamily = (s[2] == 'Products Not Categorized' ? null : s[2]);
                    fq.ForecastingTypeId = forecastTypes.get('OpportunityLineItemRevenue');                    
                }
                else {
                    fq.ForecastingTypeId = forecastTypes.get('OpportunityRevenue');
                }
                fq.QuotaAmount = rolledUpQuotaRevenue.get(k);
                fqs2Upsert.add(fq);
            }
        }

        if (forecastTypes.get('LineItemQuantityProductDate') != null ||
            forecastTypes.get('OpportunityQuantity') != null) {
            for (String k : rolledUpQuotaQuantity.keySet()) {
                // key format = UserId,StartDate,ProductFamily
                ForecastingQuota fq = new ForecastingQuota();
                String[] s = k.split(',');
                fq.QuotaOwnerId = s[0];
                fq.StartDate = Date.valueOf(s[1]);
                if (s[2] != 'null') {
                    fq.ProductFamily = (s[2] == 'Products Not Categorized' ? null : s[2]);
                    fq.ForecastingTypeId = forecastTypes.get('LineItemQuantityProductDate');                    
                }
                else {
                    fq.ForecastingTypeId = forecastTypes.get('OpportunityQuantity');
                }
                fq.QuotaQuantity = rolledUpQuotaQuantity.get(k);
                fqs2Upsert.add(fq);
            }
        }

        System.Debug('Total Records to Upsert into Forecasting Quota Object: ' + fqs2Upsert.size());

        // Process Forecasting Quota Upserts in chunks using new async threads
        List<ForecastingQuota> q = new List<ForecastingQuota>();
        for (Integer i = 0; i < fqs2Upsert.size(); i++) {
            q.add(fqs2Upsert[i]);
            if (math.mod(i+1, MAX_DML_ROWS) == 0 || i == fqs2Upsert.size()-1) {
                asyncUpsertForecastingQuota(JSON.serialize(q));
                q = new List<ForecastingQuota>();
            }
        }

        // Process Raw Quotas OwnerHierarchy Update in chunks using new async threads
        List<Raw_Quotas__c> rql = new List<Raw_Quotas__c>();
        for (Integer i = 0; i < rqs2Update.size(); i++) {
            rql.add(rqs2Update[i]);
            if (math.mod(i+1, MAX_DML_ROWS) == 0 || i == rqs2Update.size()-1) {
                asyncUpsertRawQuotas(JSON.serialize(rql));
                rql = new List<Raw_Quotas__c>();
            }
        }
    }

    @future
    public static void asyncUpsertForecastingQuota(String json2Upsert) {
        Map<String, Id> fqXref = new Map<String, Id>();
        for (ForecastingQuota fq : [select QuotaOwnerId, StartDate, ForecastingTypeId, ProductFamily, Id from ForecastingQuota]) {
            fqXref.put(fq.QuotaOwnerId + '-' + fq.StartDate + '-' + 
                       fq.ForecastingTypeId + '-' + fq.ProductFamily, fq.Id);
        }

        List<ForecastingQuota> fqs2Upsert = (List<ForecastingQuota>) JSON.deserialize(json2Upsert, List<ForecastingQuota>.class);
        for (ForecastingQuota fq : fqs2Upsert) {
            if (fqXref.get(fq.QuotaOwnerId + '-' + fq.StartDate + '-' + fq.ForecastingTypeId + '-' + fq.ProductFamily) != null) {
                fq.put('Id', fqXref.get(fq.QuotaOwnerId + '-' + fq.StartDate + '-' + 
                                        fq.ForecastingTypeId + '-' + fq.ProductFamily));
            }
        }

        System.Debug('Total Records to Upsert into Forecasting Quota Object: ' + fqs2Upsert.size());
        upsert fqs2Upsert;
    } 

    @future
    public static void asyncUpsertRawQuotas(String json2Update) {
        List<Raw_Quotas__c> rqs2Update = (List<Raw_Quotas__c>) JSON.deserialize(json2Update, List<Raw_Quotas__c>.class);

        System.Debug('Total Records to Update into Raw Quotas Object: ' + rqs2Update.size());
        update rqs2Update;
    } 
}