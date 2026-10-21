/**
 * Test data for the Restore Demo action: a contract created from a quote, with
 * the order and file that the demo flow generates. Assets are left out because
 * Revenue Cloud rejects direct inserts of AssetContractRelationship.
 */
@IsTest
public class PnP_TestDataFactory {

    public static final String RESTORE_PERMISSION_SET = 'PnP_Restore_Demo';

    /**
     * @param withRestorePermission Whether the user gets the Restore Demo permission set
     * @return An inserted admin user
     */
    public static User createAdminUser(Boolean withRestorePermission) {
        Profile adminProfile = [
            SELECT Id FROM Profile
            WHERE PermissionsModifyAllData = true AND UserType = 'Standard'
            ORDER BY CreatedDate
            LIMIT 1
        ];
        String uniqueKey = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User admin = new User(
            ProfileId = adminProfile.Id,
            LastName = 'Restore Demo Tester',
            Alias = 'rdtest',
            Email = 'restore.demo.' + uniqueKey + '@example.com',
            Username = 'restore.demo.' + uniqueKey + '@example.com.test',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Europe/Madrid'
        );
        insert admin;

        if (withRestorePermission) {
            PermissionSet restorePermissionSet = [
                SELECT Id FROM PermissionSet WHERE Name = :RESTORE_PERMISSION_SET LIMIT 1
            ];
            insert new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = restorePermissionSet.Id);
        }
        return admin;
    }

    /**
     * @return A draft contract created from a quote, with an order, an order
     *         item and a file on the contract
     */
    public static Contract createDemoContract() {
        Account account = new Account(Name = 'Restore Demo Account');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Restore Demo Opportunity',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        Quote quote = new Quote(Name = 'Restore Demo Quote', OpportunityId = opportunity.Id);
        insert quote;

        Contract contract = new Contract(
            AccountId = account.Id,
            StartDate = Date.today(),
            ContractTerm = 12,
            Status = 'Draft',
            SourceQuoteId = quote.Id
        );
        insert contract;

        Product2 product = new Product2(Name = 'Restore Demo Product', IsActive = true);
        insert product;
        PricebookEntry priceEntry = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert priceEntry;

        Order demoOrder = new Order(
            AccountId = account.Id,
            ContractId = contract.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert demoOrder;
        insert new OrderItem(
            OrderId = demoOrder.Id,
            PricebookEntryId = priceEntry.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert new ContentVersion(
            Title = 'Restore Demo Contract',
            PathOnClient = 'RestoreDemoContract.docx',
            VersionData = Blob.valueOf('demo'),
            FirstPublishLocationId = contract.Id
        );
        return contract;
    }
}
