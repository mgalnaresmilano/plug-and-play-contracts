import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPreview from '@salesforce/apex/PnP_RestoreDemoController.getPreview';
import restoreDemo from '@salesforce/apex/PnP_RestoreDemoController.restoreDemo';

export default class PnpRestoreDemo extends NavigationMixin(LightningElement) {
    preview;
    errorMessage;
    isLoading = true;
    isRestoring = false;

    _recordId;

    // Quick actions set recordId after connectedCallback, so loading starts here.
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value && value !== this._recordId) {
            this._recordId = value;
            this.loadPreview();
        }
    }

    get hasPreview() {
        return !this.isLoading && this.preview;
    }

    get isRestoreDisabled() {
        return this.isLoading || this.isRestoring || !this.preview;
    }

    get quoteLabel() {
        return this.preview?.quoteName || 'the source quote';
    }

    async loadPreview() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.preview = await getPreview({ contractId: this._recordId });
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleRestore() {
        this.isRestoring = true;
        this.errorMessage = undefined;
        try {
            const result = await restoreDemo({ contractId: this._recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Demo restored',
                    message: `Contract ${this.preview.contractNumber} and ${result.deletedRecords - 1} related records were deleted.`,
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CloseActionScreenEvent());
            this.navigateAfterRestore(result.quoteId);
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            this.isRestoring = false;
        }
    }

    navigateAfterRestore(quoteId) {
        const pageReference = quoteId
            ? { type: 'standard__recordPage', attributes: { recordId: quoteId, actionName: 'view' } }
            : { type: 'standard__objectPage', attributes: { objectApiName: 'Contract', actionName: 'home' } };
        this[NavigationMixin.Navigate](pageReference, true);
    }
}

function reduceError(error) {
    return error?.body?.message || error?.message || 'Unexpected error.';
}
