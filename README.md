**Deploy to Dev Org/Prod:** [![Deploy to Salesforce](https://andrewfawcett.files.wordpress.com/2014/09/deploy.png)](https://githubsfdeploy.herokuapp.com/app/githubdeploy/sriram-venkatraman/Automated-Quota-Rollup)

**Deploy to Sandbox:** [![Deploy to Salesforce](https://andrewfawcett.files.wordpress.com/2014/09/deploy.png)](https://githubsfdeploy-sandbox.herokuapp.com/app/githubdeploy/sriram-venkatraman/Automated-Quota-Rollup)

## Sample Execution

```
ID jobID = System.enqueueJob(new RollupQuota());
System.Debug('Job: ' + jobID);
```

# Automated Quota Rollup

_Note: Still tidying up with test classes and documentation. Functionality seems to work reasonably well although I haven't done extensive test_

This framework uses a custom object called **Raw Quotas** to capture raw quotas for every forecast user. This custom is then used to roll-up Revenue & Quantity up User's Forecast Hierarchy using **RollupQuota** class. **RollupQuota** works only for Collaborative Forecasting. This class has been coded only to support the following Forecasting Types to support my current use case -

- Opportunity Revenue
- Opportunity Line Item Revenue
- Line Item Quantity Product Date

Owner Hierarchy built in **RollupQuota** uses the following hierarchy -

```
     Quota Owner User    <----------Loop until you reach top of chain-----.
         > Quota Owner User Role                                          |
             > Quota Owner's Parent User Role                             |
                 > Quota Owner's Parent User Role - Forecast User --------'
                     (this forecast manager assigned for the role)
```

Required fields to be populate in **Raw Quotas** custom object are -

- Forecast Owner (active user)
- Start Date of the Forecast Period
- Forecast Amount for Revenue Forecast required (only populate either this)
- Forecast Quantity for Quantity Forecast required (or this)
- Product Family

## Important

- Class **RollupQuota** supports only Collaborative Forecasting
- After loading **Raw Quotas** custom object, you have to execute the Queueable apex class **RollupQuota**
- Do not rollup Revenue or Quantity on you own when loading into **Raw Quotas** custom object. The Queueable class will do the rollup and load data into **ForecastingQuota** standard object
- Manager's can also have their own Quotas. They will be included when rolling up in addition to their subordinates' quotas

## Dev, Build and Test

## Resources

## Description of Files and Directories

## Issues
