public with sharing class RollupQuota {
    static final Integer MAX_ITERATIONS = 50;
    
    public RollupQuota() {

    }

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
        Map<String, String> roleManagerUserMap = new Map<String, String>();
        for ( UserRole ur : urList.values() ) {
            if (ur.ParentRoleId != null) {
                roleManagerUserMap.put(ur.Id, urList.get(ur.ParentRoleId).ForecastUserId);
            }
        }

        Map<String, String> userManagerMap = new Map<String, String>();

        for (User u : [select Id, 
                            UserRoleId
                    from   User
                    where  IsActive = true]){
            if (u.UserRoleId != null && roleManagerUserMap.get(u.UserRoleId) != null) {
                userManagerMap.put(u.Id, roleManagerUserMap.get(u.UserRoleId));
                // System.Debug('User: ' + u.Id + ' | Manager: ' + roleManagerUserMap.get(u.UserRoleId));
            }
        }

        List<FlattenedQuotas> fqs = new List<FlattenedQuotas>();

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

        Integer currentIteration = 0;
        Integer currentIdx = 0;
        Boolean parentsFound = true;
        Integer parentCount = 0;
        String managerId;
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
        for (FlattenedQuotas fq : fqs) {
            for (String o : fq.ownerHierarchy.split(';')) {
                if (rolledUpQuotaRevenue.get(o + ',' + fq.startDate + ',' + fq.productFamily) == null) {
                    rolledUpQuotaRevenue.put(o + ',' + fq.startDate + ',' + fq.productFamily, fq.amount);
                }
                else {
                    rolledUpQuotaRevenue.put(o + ',' + fq.startDate + ',' + fq.productFamily, 
                                            fq.amount + rolledUpQuotaRevenue.get(o + ',' + fq.startDate + ',' + fq.productFamily));
                }
            }
        }

        Map<String, Decimal> rolledUpQuotaQuantity = new Map<String, Decimal>();
        for (FlattenedQuotas fq : fqs) {
            for (String o : fq.ownerHierarchy.split(';')) {
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
}
