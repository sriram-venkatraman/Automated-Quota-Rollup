trigger RawQuotasTrigger on Raw_Quotas__c (before insert, before update) {

    for(Raw_Quotas__c rq : Trigger.New) {
        if (Trigger.isInsert ||
            (Trigger.isUpdate && 
                (rq.OwnerId != Trigger.oldMap.get(rq.Id).OwnerId ||
                 rq.Start_Date__c != Trigger.oldMap.get(rq.Id).Start_Date__c ||
                 rq.Product_Family__c != Trigger.oldMap.get(rq.Id).Product_Family__c))) { 
            rq.Unique_Key__c = rq.OwnerId + '-' + rq.Start_Date__c + '-' + rq.Product_Family__c;
        }
    }  
    
}