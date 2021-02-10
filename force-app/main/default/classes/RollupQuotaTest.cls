@isTest
public class RollupQuotaTest {
    @testSetup
    static void setup() {
        Profile p = [select Id from Profile where Name = 'Standard User'];

        UserRole pur = new UserRole(Name='Dummy Parent Role');
        insert pur;
        System.Debug('Parent Role: ' + pur);

        UserRole eur = new UserRole(Name='Dummy Employee Role', ParentRoleId=pur.Id);
        insert eur;
        System.Debug('Employee Role: ' + eur);

        User mgrU = new User(FirstName='Manager', 
                            LastName='Test User1', 
                            UserName='mgrtusr1@dummy.org', 
                            Email='mgrtusr1@dummy.org',
                            Alias='mgrtusr1',
                            ProfileId=p.Id,
                            UserRoleId=pur.Id,
                            ForecastEnabled=true,
                            EmailEncodingKey='UTF-8',
                            LanguageLocaleKey='en_US', 
                            LocaleSidKey='en_US',
                            Bypass_Role_Assignment__c=true,
                            TimeZoneSidKey='America/Los_Angeles'
                            );
        insert mgrU;
        System.Debug('Manager User: ' + mgrU);

        pur.put('ForecastUserId',mgrU.Id);
        update pur;

        User empU = new User(FirstName='Employee', 
                            LastName='Test User1', 
                            UserName='emptusr1@dummy.org', 
                            Email='emptusr1@dummy.org',
                            Alias='emptusr1',
                            ProfileId=p.Id,
                            UserRoleId=eur.Id,
                            ManagerId=mgrU.Id,
                            ForecastEnabled=true,
                            EmailEncodingKey='UTF-8',
                            LanguageLocaleKey='en_US', 
                            LocaleSidKey='en_US',
                            Bypass_Role_Assignment__c=true,
                            TimeZoneSidKey='America/Los_Angeles'
                            );
        insert empU;

    }

    static testmethod void testForecastAmount() {
        Id OpportunityLineItemRevenueId;
        Id OpportunityRevenueId;
        try {
            OpportunityLineItemRevenueId = [select Id, DeveloperName 
                                                from ForecastingType 
                                                where IsActive = true 
                                                and DeveloperName = 'OpportunityLineItemRevenue' 
                                                limit 1].Id;
        } catch (Exception e) {}

        try {
            OpportunityRevenueId = [select Id, DeveloperName 
                                        from ForecastingType 
                                        where IsActive = true 
                                        and DeveloperName = 'OpportunityRevenue' 
                                        limit 1].Id;
        } catch (Exception e) {}

        List<Raw_Quotas__c> rqs = new List<Raw_Quotas__c>();
        rqs.add(new Raw_Quotas__c(Start_Date__c=Date.newInstance(2021, 01, 01),
                                    Amount__c=10000,
                                    Product_Family__c='Products Not Categorized',
                                    Is_Active__c=true,
                                    OwnerId=[select id from User where username = 'emptusr1@dummy.org' limit 1].id));
        insert rqs;
        System.debug('Users: ' + [select id, name, userrole.name, manager.name, profile.name from user where username like '%dummy.org']);
        System.debug('Raw Quotas: ' + [select id, name, Start_Date__c, Product_Family__c, Amount__c, Owner.Name from Raw_Quotas__c ]);
        
        // Create our Queueable instance
        RollupQuota rq = new RollupQuota();

        // startTest/stopTest block to force async processes to run
        Test.startTest();
        System.enqueueJob(rq);
        Test.stopTest();

        // Validate the job ran. Check if Product Line item is correct
        if (OpportunityLineItemRevenueId != null) {
            System.assertEquals(2, [select count() from ForecastingQuota where ForecastingTypeId = :OpportunityLineItemRevenueId], 'Unexpected total number of quota records - Product Family Revenue');
            System.assertEquals(20000, [SELECT sum(QuotaAmount) sumAmount FROM ForecastingQuota where ForecastingTypeId = :OpportunityLineItemRevenueId][0].get('sumAmount'), 'Unexpected total QuotaAmount - Product Family Revenue');
            System.assertNotEquals(null, [SELECT Owner_Hierarchy__c FROM Raw_Quotas__c][0].Owner_Hierarchy__c, 'Owner Hierarchy not updated - Product Family Revenue');
        }

        if (OpportunityRevenueId != null) {
            System.assertEquals(2, [select count() from ForecastingQuota where ForecastingTypeId = :OpportunityRevenueId], 'Unexpected total number of quota records - Revenue');
            System.assertEquals(20000, [SELECT sum(QuotaAmount) sumAmount FROM ForecastingQuota where ForecastingTypeId = :OpportunityRevenueId][0].get('sumAmount'), 'Unexpected total QuotaAmount - Revenue');
            System.assertNotEquals(null, [SELECT Owner_Hierarchy__c FROM Raw_Quotas__c][0].Owner_Hierarchy__c, 'Owner Hierarchy not updated - Revenue');
        }
    }

    static testmethod void testForecastQuantity() {
        Id LineItemQuantityProductDateId;
        Id OpportunityQuantityId;
        try {
            LineItemQuantityProductDateId = [select Id, DeveloperName 
                                            from ForecastingType 
                                            where IsActive = true 
                                            and DeveloperName = 'LineItemQuantityProductDate' 
                                            limit 1].Id;
        } catch (Exception e) {}

        try {
            OpportunityQuantityId = [select Id, DeveloperName 
                                    from ForecastingType 
                                    where IsActive = true 
                                    and DeveloperName = 'OpportunityQuantity' 
                                    limit 1].Id;
        } catch (Exception e) {}
        
        List<Raw_Quotas__c> rqs = new List<Raw_Quotas__c>();
        rqs.add(new Raw_Quotas__c(Start_Date__c=Date.newInstance(2021, 01, 01),
                                    Quantity__c=1000,
                                    Product_Family__c='Products Not Categorized',
                                    Is_Active__c=true,
                                    OwnerId=[select id from User where username = 'emptusr1@dummy.org' limit 1].id));
        insert rqs;
        System.debug('Users: ' + [select id, name, userrole.name, manager.name, profile.name from user where username like '%dummy.org']);
        System.debug('Raw Quotas: ' + [select id, name, Start_Date__c, Product_Family__c, Amount__c, Owner.Name from Raw_Quotas__c ]);
        
        // Create our Queueable instance
        RollupQuota rq = new RollupQuota();

        // startTest/stopTest block to force async processes to run
        Test.startTest();
        System.enqueueJob(rq);
        Test.stopTest();

        // Validate the job ran. 
        if (LineItemQuantityProductDateId != null) {
            System.assertEquals(2, [select count() from ForecastingQuota where ForecastingTypeId = :LineItemQuantityProductDateId], 'Unexpected total number of quota records - Product Family Quantity');
            System.assertEquals(2000, [SELECT sum(QuotaQuantity) sumQuantity FROM ForecastingQuota where ForecastingTypeId = :LineItemQuantityProductDateId][0].get('sumQuantity'), 'Unexpected total Quota Quantity - Product Family Quantity');
            System.assertNotEquals(null, [SELECT Owner_Hierarchy__c FROM Raw_Quotas__c][0].Owner_Hierarchy__c, 'Owner Hierarchy not updated - Product Family Quantity');
        }

        if (OpportunityQuantityId != null) {
            System.assertEquals(2, [select count() from ForecastingQuota where ForecastingTypeId = :OpportunityQuantityId], 'Unexpected total number of quota records - Quantity');
            System.assertEquals(2000, [SELECT sum(QuotaQuantity) sumQuantity FROM ForecastingQuota where ForecastingTypeId = :OpportunityQuantityId][0].get('sumQuantity'), 'Unexpected total Quota Quantity -  Quantity');
            System.assertNotEquals(null, [SELECT Owner_Hierarchy__c FROM Raw_Quotas__c][0].Owner_Hierarchy__c, 'Owner Hierarchy not updated - Product Family Quantity');
        }
    }
}