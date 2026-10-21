/**
 * Collects every record generated from a demo contract, grouped into steps in
 * the order they can be deleted. Built once and used both for the preview shown
 * to the user and for the deletion itself, so both always agree.
 *
 * Order matters: fulfillment lines block their order items, assets block their
 * contract relationships, and a fulfillment plan can only go once its order is
 * gone. The contract itself is the last step.
 */
public with sharing class PnP_RestoreDemoPlan {

    private static final String USER_KEY_PREFIX = '005';

    /**
     * A group of records of one object, deleted together.
     */
    public class Step {
        public String label;
        public List<SObject> records;
        public Boolean isOrderStep = false;

        public Step(String label, List<SObject> records) {
            this.label = label;
            this.records = records;
        }
    }

    public Contract contract { get; private set; }
    public List<Step> steps { get; private set; }

    private Set<Id> orderIds;
    private Set<Id> orderItemIds;
    private Set<Id> assetIds;
    private Set<Id> documentVersionIds;
    // A file can't be deleted while one of these links points to it, and
    // deleting the link deletes the file with it.
    private List<ContractDocVerContentDoc> documentFileLinks;

    /**
     * @param contractId Contract to restore
     * @throws PnP_RestoreDemoException when the contract does not exist
     */
    public PnP_RestoreDemoPlan(Id contractId) {
        List<Contract> contracts = [
            SELECT Id, ContractNumber, Status, SourceQuoteId, SourceQuote.Name
            FROM Contract
            WHERE Id = :contractId
            LIMIT 1
        ];
        if (contracts.isEmpty()) {
            throw new PnP_RestoreDemoException('Contract not found: ' + contractId);
        }
        contract = contracts[0];
        collectIds();
        buildSteps();
    }

    /**
     * @return Total number of records the restore will delete, contract included
     */
    public Integer getTotalRecords() {
        Integer total = 0;
        for (Step step : steps) {
            total += step.records.size();
        }
        return total;
    }

    private void collectIds() {
        orderIds = new Map<Id, Order>([SELECT Id FROM Order WHERE ContractId = :contract.Id]).keySet();
        orderItemIds = new Map<Id, OrderItem>([SELECT Id FROM OrderItem WHERE OrderId IN :orderIds]).keySet();
        documentVersionIds = new Map<Id, ContractDocumentVersion>(
            [SELECT Id FROM ContractDocumentVersion WHERE ContractId = :contract.Id]
        ).keySet();
        documentFileLinks = [
            SELECT Id, ContentDocumentId FROM ContractDocVerContentDoc
            WHERE ContractDocumentVersionId IN :documentVersionIds
        ];

        assetIds = new Set<Id>();
        for (AssetContractRelationship relation : [
            SELECT AssetId FROM AssetContractRelationship WHERE ContractId = :contract.Id
        ]) {
            assetIds.add(relation.AssetId);
        }
        for (AssetActionSource source : [
            SELECT AssetAction.AssetId FROM AssetActionSource WHERE ReferenceEntityItemId IN :orderItemIds
        ]) {
            assetIds.add(source.AssetAction.AssetId);
        }
    }

    private void buildSteps() {
        Set<String> fulfillmentSources = new Set<String>();
        for (Id orderId : orderIds) {
            fulfillmentSources.add(orderId);
        }
        for (Id orderItemId : orderItemIds) {
            fulfillmentSources.add(orderItemId);
        }
        Set<Id> fulfillmentOrderIds = new Map<Id, FulfillmentOrder>(
            [SELECT Id FROM FulfillmentOrder WHERE OrderId IN :orderIds]
        ).keySet();
        Set<Id> fulfillmentLineIds = new Map<Id, FulfillmentOrderLineItem>(
            [SELECT Id FROM FulfillmentOrderLineItem WHERE FulfillmentOrderId IN :fulfillmentOrderIds]
        ).keySet();
        Set<Id> fulfillmentPlanIds = new Map<Id, FulfillmentPlan>(
            [SELECT Id FROM FulfillmentPlan WHERE SourceIdentifier IN :fulfillmentSources]
        ).keySet();

        steps = new List<Step>();
        steps.add(new Step('Fulfillment line sources', [
            SELECT Id FROM FulfillmentLineSourceRel
            WHERE SourceLineItemId IN :orderItemIds OR FulfilmentOrderLineId IN :fulfillmentLineIds
        ]));
        steps.add(new Step('Fulfillment step sources', [
            SELECT Id FROM FulfillmentStepSource WHERE SourceLineItemId IN :orderItemIds
        ]));
        steps.add(new Step('Fulfillment order lines', [
            SELECT Id FROM FulfillmentOrderLineItem WHERE Id IN :fulfillmentLineIds
        ]));
        steps.add(new Step('Fulfillment orders', [
            SELECT Id FROM FulfillmentOrder WHERE Id IN :fulfillmentOrderIds
        ]));
        steps.add(new Step('Fulfillment steps', [
            SELECT Id FROM FulfillmentStep WHERE FulfillmentPlanId IN :fulfillmentPlanIds
        ]));
        steps.add(new Step('Usage entitlements', [
            SELECT Id FROM TransactionUsageEntitlement WHERE OrderItemId IN :orderItemIds
        ]));
        addAssetSteps();
        steps.add(new Step('Document generation requests', getDocumentGenerationProcesses()));
        steps.add(new Step('Contract document files', documentFileLinks));
        steps.add(new Step('Other contract files', getContractFiles()));

        Step orderStep = new Step('Orders', [SELECT Id, Status FROM Order WHERE Id IN :orderIds]);
        orderStep.isOrderStep = true;
        steps.add(orderStep);
        steps.add(new Step('Fulfillment plans', [
            SELECT Id FROM FulfillmentPlan WHERE Id IN :fulfillmentPlanIds
        ]));
        steps.add(new Step('Contract', new List<SObject>{ contract }));
    }

    private void addAssetSteps() {
        steps.add(new Step('Asset relationships', [
            SELECT Id FROM AssetRelationship WHERE AssetId IN :assetIds OR RelatedAssetId IN :assetIds
        ]));
        steps.add(new Step('Asset contract relationships', [
            SELECT Id FROM AssetContractRelationship WHERE ContractId = :contract.Id OR AssetId IN :assetIds
        ]));
        steps.add(new Step('Asset state periods', [
            SELECT Id FROM AssetStatePeriod WHERE AssetId IN :assetIds
        ]));
        steps.add(new Step('Asset action sources', [
            SELECT Id FROM AssetActionSource WHERE AssetAction.AssetId IN :assetIds
        ]));
        steps.add(new Step('Asset actions', [
            SELECT Id FROM AssetAction WHERE AssetId IN :assetIds
        ]));
        steps.add(new Step('Assets', [SELECT Id FROM Asset WHERE Id IN :assetIds]));
    }

    private List<SObject> getDocumentGenerationProcesses() {
        Set<String> references = new Set<String>{ contract.Id };
        for (Id versionId : documentVersionIds) {
            references.add(versionId);
        }
        return [SELECT Id FROM DocumentGenerationProcess WHERE ReferenceObject IN :references];
    }

    /**
     * Files linked to the contract or its document versions. A file that is
     * also shared with any other record (a template, a library) is kept.
     */
    private List<SObject> getContractFiles() {
        Set<Id> ownerIds = new Set<Id>(documentVersionIds);
        ownerIds.add(contract.Id);

        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :ownerIds
        ]) {
            documentIds.add(link.ContentDocumentId);
        }
        if (documentIds.isEmpty()) {
            return new List<SObject>();
        }

        Set<Id> sharedElsewhere = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
        ]) {
            Boolean isOwnRecord = ownerIds.contains(link.LinkedEntityId);
            Boolean isUser = String.valueOf(link.LinkedEntityId).startsWith(USER_KEY_PREFIX);
            if (!isOwnRecord && !isUser) {
                sharedElsewhere.add(link.ContentDocumentId);
            }
        }
        documentIds.removeAll(sharedElsewhere);
        for (ContractDocVerContentDoc fileLink : documentFileLinks) {
            documentIds.remove(fileLink.ContentDocumentId);
        }
        return [SELECT Id FROM ContentDocument WHERE Id IN :documentIds];
    }
}
