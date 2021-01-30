public with sharing class RollupQuota {
    private static final Integer MAX_ITERATIONS = 50;
    private static Map<String, String> forecastTypes;
    
    public RollupQuota() {
        if (forecastTypes == null) {
            forecastTypes = new Map<String, String>();
            for (ForecastingType ft : [select Id, DeveloperName
                                       from ForecastingType
                                       where IsActive = true
                                       and DeveloperName in ('OpportunityRevenue',
                                                             'OpportunityQuantity',
                                                             'OpportunityLineItemRevenue',
                                                             'OpportunityLineItemQuantity')]) {
                forecastTypes.put(ft.DeveloperName, ft.Id);
            }
        }
        System.Debug('Forecast Types: ' + forecastTypes);
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
    }

    public void doRollup() {
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

        // To get User and Manager User Id as defined in the Owner Hierarchy above, let's start with User & Role Id
        // and get Role Id's associated Parent's Forecast User Id; Resultant map contains User Id & Manager Id
        // per definition
        for (User u : [select Id, 
                              UserRoleId
                       from   User
                       where  IsActive = true]){
            if (u.UserRoleId != null && roleManagerUserMap.get(u.UserRoleId) != null) {
                userManagerMap.put(u.Id, roleManagerUserMap.get(u.UserRoleId));
            }
        }

        List<FlattenedQuotas> fqs = new List<FlattenedQuotas>();

        // Get all Quota data from the Raw Quota object
        for (Raw_Quotas__c rq : [select OwnerId,
                                        Start_Date__c,
                                        Amount__c,
                                        Quantity__c,
                                        Product_Family__c
                                from	Raw_Quotas__c]) {
            FlattenedQuotas fq = new FlattenedQuotas();
            fq.ownerHierarchy = rq.OwnerId;
            fq.startDate = rq.Start_Date__c;
            fq.amount = rq.Amount__c;
            fq.quantity = rq.Quantity__c;
            fq.productFamily = rq.Product_Family__c;
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
        // Now break the Owner Hierarchy in to granular user quota, group by User Id, Start Date, Product Family and
        // sum of Amount or sum of Quantity
        // key = UserId,StartDate,ProductFamily
        for (FlattenedQuotas fq : fqs) {
            for (String o : fq.ownerHierarchy.split(';')) {
                // Revenue Rollup
                if (fq.amount != null) {
                    if (rolledUpQuotaRevenue.get(o + ',' + fq.startDate + ',' + fq.productFamily) == null) {
                        rolledUpQuotaRevenue.put(o + ',' + fq.startDate + ',' + fq.productFamily, fq.amount);
                    }
                    else {
                        rolledUpQuotaRevenue.put(o + ',' + fq.startDate + ',' + fq.productFamily, 
                                                fq.amount + rolledUpQuotaRevenue.get(o + ',' + fq.startDate + ',' + fq.productFamily));
                    }
                }

                // Quantity Rollup
                if (fq.quantity != null) {
                    if (rolledUpQuotaQuantity.get(o + ',' + fq.startDate + ',' + fq.productFamily) == null) {
                        rolledUpQuotaQuantity.put(o + ',' + fq.startDate + ',' + fq.productFamily, fq.quantity);
                    }
                    else {
                        rolledUpQuotaQuantity.put(o + ',' + fq.startDate + ',' + fq.productFamily, 
                                                fq.quantity + rolledUpQuotaQuantity.get(o + ',' + fq.startDate + ',' + fq.productFamily));
                    }
                }
            }
        }

        System.Debug('Total Rolled Up Amount: ' + rolledUpQuotaRevenue.size());
        System.Debug('Total Rolled Up Quantity: ' + rolledUpQuotaQuantity.size());

        List<ForecastingQuota> fql = new List<ForecastingQuota>();
        if (forecastTypes.get('OpportunityLineItemRevenue') != null ||
            forecastTypes.get('OpportunityRevenue') != null) {
            for (String k : rolledUpQuotaRevenue.keySet()) {
                // key format = UserId,StartDate,ProductFamily
                ForecastingQuota fq = new ForecastingQuota();
                String[] s = k.split(',');
                fq.QuotaOwnerId = s[0];
                fq.StartDate = Date.valueOf(s[1]);
                if (s[2] != 'null') {
                    fq.ProductFamily = s[2];
                    fq.ForecastingTypeId = forecastTypes.get('OpportunityLineItemRevenue');                    
                }
                else {
                    fq.ForecastingTypeId = forecastTypes.get('OpportunityRevenue');

                }
                fq.QuotaAmount = rolledUpQuotaRevenue.get(k);
                fql.add(fq);
            }
        }

        if (forecastTypes.get('OpportunityLineItemQuantity') != null ||
            forecastTypes.get('OpportunityQuantity') != null) {
            for (String k : rolledUpQuotaQuantity.keySet()) {
                // key format = UserId,StartDate,ProductFamily
                ForecastingQuota fq = new ForecastingQuota();
                String[] s = k.split(',');
                fq.QuotaOwnerId = s[0];
                fq.StartDate = Date.valueOf(s[1]);
                if (s[2] != 'null') {
                    fq.ProductFamily = s[2];
                    fq.ForecastingTypeId = forecastTypes.get('OpportunityLineItemQuantity');                    
                }
                else {
                    fq.ForecastingTypeId = forecastTypes.get('OpportunityQuantity');

                }
                fq.QuotaAmount = rolledUpQuotaQuantity.get(k);
                fql.add(fq);
            }
        }

        System.Debug('Total Records to Insert into Forecasting Quota Object: ' + fql.size());
        System.Debug(fql);
    }
}
