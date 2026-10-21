@IsTest
private class PnP_RestoreDemoServiceTest {

    @TestSetup
    static void setup() {
        PnP_TestDataFactory.createAdminUser(true);
        // Setup objects (users) and business records can't share a transaction.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PnP_TestDataFactory.createDemoContract();
        }
    }

    private static User getRestoreUser() {
        return [
            SELECT Id FROM User
            WHERE LastName = 'Restore Demo Tester'
            AND Id IN (
                SELECT AssigneeId FROM PermissionSetAssignment
                WHERE PermissionSet.Name = :PnP_TestDataFactory.RESTORE_PERMISSION_SET
            )
            LIMIT 1
        ];
    }

    private static Contract getContract() {
        return [SELECT Id, ContractNumber, SourceQuoteId FROM Contract LIMIT 1];
    }

    @IsTest
    static void getPreview_listsContractAndRelatedRecords() {
        // Given
        Contract contract = getContract();
        PnP_RestoreDemoService.Preview preview;

        // When
        System.runAs(getRestoreUser()) {
            Test.startTest();
            preview = PnP_RestoreDemoService.getPreview(contract.Id);
            Test.stopTest();
        }

        // Then
        Assert.areEqual(contract.ContractNumber, preview.contractNumber, 'Preview should show the contract number');
        Assert.areEqual(contract.SourceQuoteId, preview.quoteId, 'Preview should point to the source quote');
        Map<String, Integer> countsByLabel = new Map<String, Integer>();
        for (PnP_RestoreDemoService.PreviewLine line : preview.lines) {
            countsByLabel.put(line.label, line.count);
        }
        Assert.areEqual(1, countsByLabel.get('Orders'), 'Preview should count the order');
        Assert.areEqual(1, countsByLabel.get('Other contract files'), 'Preview should count the contract file');
        Assert.areEqual(1, countsByLabel.get('Contract'), 'Preview should count the contract itself');
        Assert.isFalse(countsByLabel.containsKey('Assets'), 'Empty steps should be left out of the preview');
        Assert.areEqual(3, preview.totalRecords, 'Total should add up every step');
    }

    @IsTest
    static void restore_deletesContractAndRelatedRecords() {
        // Given
        Contract contract = getContract();
        update new Contract(Id = contract.Id, Status = 'Activated');
        update new Order(Id = [SELECT Id FROM Order LIMIT 1].Id, Status = 'Activated');
        PnP_RestoreDemoService.Result result;

        // When
        System.runAs(getRestoreUser()) {
            Test.startTest();
            result = PnP_RestoreDemoService.restore(contract.Id);
            Test.stopTest();
        }

        // Then
        Assert.areEqual(contract.SourceQuoteId, result.quoteId, 'Result should point back to the source quote');
        Assert.areEqual(3, result.deletedRecords, 'Every planned record should be deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Contract WHERE Id = :contract.Id], 'Contract should be deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Order], 'Activated order should be deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument], 'Contract file should be deleted');
        Assert.areEqual(1, [SELECT COUNT() FROM Quote WHERE Id = :contract.SourceQuoteId], 'Quote should be kept');
    }

    @IsTest
    static void restore_withoutPermission_throwsAndDeletesNothing() {
        // Given
        Contract contract = getContract();
        User userWithoutPermission;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            userWithoutPermission = PnP_TestDataFactory.createAdminUser(false);
        }
        PnP_RestoreDemoException caught;

        // When
        System.runAs(userWithoutPermission) {
            Test.startTest();
            try {
                PnP_RestoreDemoService.restore(contract.Id);
            } catch (PnP_RestoreDemoException e) {
                caught = e;
            }
            Test.stopTest();
        }

        // Then
        Assert.isNotNull(caught, 'Restore should be refused without the custom permission');
        Assert.isTrue(caught.getMessage().contains('permission'), 'Error should mention the missing permission');
        Assert.areEqual(1, [SELECT COUNT() FROM Contract WHERE Id = :contract.Id], 'Contract should be kept');
    }

    @IsTest
    static void getPreview_missingContract_throws() {
        // Given
        Contract contract = getContract();
        delete [SELECT Id FROM Order];
        delete contract;
        PnP_RestoreDemoException caught;

        // When
        System.runAs(getRestoreUser()) {
            Test.startTest();
            try {
                PnP_RestoreDemoService.getPreview(contract.Id);
            } catch (PnP_RestoreDemoException e) {
                caught = e;
            }
            Test.stopTest();
        }

        // Then
        Assert.isNotNull(caught, 'A deleted contract should raise an error');
        Assert.isTrue(caught.getMessage().contains('not found'), 'Error should say the contract was not found');
    }

    @IsTest
    static void controller_wrapsServiceErrorsForTheComponent() {
        // Given
        Contract contract = getContract();
        AuraHandledException caught;
        PnP_RestoreDemoService.Preview preview;

        // When
        System.runAs(getRestoreUser()) {
            Test.startTest();
            preview = PnP_RestoreDemoController.getPreview(contract.Id);
            try {
                PnP_RestoreDemoController.restoreDemo(null);
            } catch (AuraHandledException e) {
                caught = e;
            }
            Test.stopTest();
        }

        // Then
        Assert.areEqual(contract.ContractNumber, preview.contractNumber, 'Controller should return the preview');
        Assert.isNotNull(caught, 'Controller should surface service errors as AuraHandledException');
        Assert.areEqual('A contract is required.', caught.getMessage(), 'Controller should keep the service message');
    }

    @IsTest
    static void controller_restoreDemo_returnsQuote() {
        // Given
        Contract contract = getContract();
        PnP_RestoreDemoService.Result result;

        // When
        System.runAs(getRestoreUser()) {
            Test.startTest();
            result = PnP_RestoreDemoController.restoreDemo(contract.Id);
            Test.stopTest();
        }

        // Then
        Assert.areEqual(contract.SourceQuoteId, result.quoteId, 'Controller should return the source quote');
    }
}
