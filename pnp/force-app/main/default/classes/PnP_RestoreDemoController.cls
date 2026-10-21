/**
 * Backs the Restore Demo quick action on Contract.
 */
public with sharing class PnP_RestoreDemoController {

    /**
     * @param contractId Contract shown in the quick action
     * @return What a restore would delete
     */
    @AuraEnabled
    public static PnP_RestoreDemoService.Preview getPreview(Id contractId) {
        try {
            return PnP_RestoreDemoService.getPreview(contractId);
        } catch (PnP_RestoreDemoException e) {
            throw toAuraException(e);
        }
    }

    /**
     * @param contractId Contract to delete with everything generated from it
     * @return The source quote to go back to and how many records were deleted
     */
    @AuraEnabled
    public static PnP_RestoreDemoService.Result restoreDemo(Id contractId) {
        try {
            return PnP_RestoreDemoService.restore(contractId);
        } catch (PnP_RestoreDemoException e) {
            throw toAuraException(e);
        }
    }

    private static AuraHandledException toAuraException(Exception e) {
        AuraHandledException auraException = new AuraHandledException(e.getMessage());
        auraException.setMessage(e.getMessage());
        return auraException;
    }
}
