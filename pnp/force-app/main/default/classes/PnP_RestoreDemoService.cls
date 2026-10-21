/**
 * Resets the demo by deleting a contract and everything generated from it
 * (order, fulfillment, assets, contract documents and files), so a new
 * contract can be created again from the same quote.
 *
 * The deletion is all-or-nothing: if any step fails, nothing is deleted.
 * Posted invoices are never deletable on the platform and stay behind.
 */
public with sharing class PnP_RestoreDemoService {

    @TestVisible
    private static final String CUSTOM_PERMISSION = 'PnP_Restore_Demo';
    private static final String DRAFT_STATUS = 'Draft';

    /**
     * Summary of what a restore deletes, step by step.
     */
    public class Preview {
        @AuraEnabled public String contractNumber;
        @AuraEnabled public String contractStatus;
        @AuraEnabled public Id quoteId;
        @AuraEnabled public String quoteName;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public List<PreviewLine> lines = new List<PreviewLine>();
    }

    /**
     * One object in the preview and how many of its records will be deleted.
     */
    public class PreviewLine {
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;

        public PreviewLine(String label, Integer count) {
            this.label = label;
            this.count = count;
        }
    }

    /**
     * Outcome of a restore.
     */
    public class Result {
        @AuraEnabled public Id quoteId;
        @AuraEnabled public Integer deletedRecords;
    }

    /**
     * @param contractId Contract to inspect
     * @return What a restore of this contract would delete
     * @throws PnP_RestoreDemoException when the user lacks the permission or the contract is missing
     */
    public static Preview getPreview(Id contractId) {
        checkAccess(contractId);
        PnP_RestoreDemoPlan plan = new PnP_RestoreDemoPlan(contractId);

        Preview preview = new Preview();
        preview.contractNumber = plan.contract.ContractNumber;
        preview.contractStatus = plan.contract.Status;
        preview.quoteId = plan.contract.SourceQuoteId;
        preview.quoteName = plan.contract.SourceQuote?.Name;
        preview.totalRecords = plan.getTotalRecords();
        for (PnP_RestoreDemoPlan.Step step : plan.steps) {
            if (!step.records.isEmpty()) {
                preview.lines.add(new PreviewLine(step.label, step.records.size()));
            }
        }
        return preview;
    }

    /**
     * Deletes the contract and all records generated from it.
     *
     * @param contractId Contract to delete
     * @return The source quote to go back to and how many records were deleted
     * @throws PnP_RestoreDemoException when the user lacks the permission, the
     *         contract is missing or any record refuses to delete
     */
    public static Result restore(Id contractId) {
        checkAccess(contractId);
        PnP_RestoreDemoPlan plan = new PnP_RestoreDemoPlan(contractId);

        Savepoint savepoint = Database.setSavepoint();
        String currentStep;
        try {
            for (PnP_RestoreDemoPlan.Step step : plan.steps) {
                currentStep = step.label;
                deleteStep(step);
            }
        } catch (DmlException e) {
            Database.rollback(savepoint);
            throw new PnP_RestoreDemoException(
                'Nothing was deleted. ' + currentStep + ' could not be deleted: ' + e.getDmlMessage(0), e
            );
        }

        Result result = new Result();
        result.quoteId = plan.contract.SourceQuoteId;
        result.deletedRecords = plan.getTotalRecords();
        return result;
    }

    private static void deleteStep(PnP_RestoreDemoPlan.Step step) {
        if (step.records.isEmpty()) {
            return;
        }
        if (step.isOrderStep) {
            // An activated order cannot be deleted until it is back in draft.
            List<Order> activeOrders = new List<Order>();
            for (Order demoOrder : (List<Order>) step.records) {
                if (demoOrder.Status != DRAFT_STATUS) {
                    activeOrders.add(new Order(Id = demoOrder.Id, Status = DRAFT_STATUS));
                }
            }
            update activeOrders;
        }
        delete step.records;
    }

    private static void checkAccess(Id contractId) {
        if (contractId == null) {
            throw new PnP_RestoreDemoException('A contract is required.');
        }
        if (!FeatureManagement.checkPermission(CUSTOM_PERMISSION)) {
            throw new PnP_RestoreDemoException('You need the Restore Demo permission to use this action.');
        }
    }
}
