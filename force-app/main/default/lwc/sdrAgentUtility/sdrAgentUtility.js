import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import analyzeLead from '@salesforce/apex/LeadAnalysisService.analyzeLead';

export default class SdrAgentUtility extends LightningElement {
    @api height = 600;
    @api label = 'SDR AI Agent';
    @api recordId;
    @api objectApiName;

    @track selectedLeadId;
    @track analysisResult;
    @track errorMessage;
    @track isAnalyzing = false;

    // Fires reactively whenever the user navigates to a different page
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) return;
        const attributes = pageRef.attributes || {};

        let detectedLeadId = null;

        if (
            pageRef.type === 'standard__recordPage' &&
            attributes.objectApiName === 'Lead' &&
            attributes.recordId
        ) {
            // Utility bar context: user is on a Lead record page
            detectedLeadId = attributes.recordId;
        } else if (this.recordId && this.objectApiName === 'Lead') {
            // Component placed directly on a Lead record page
            detectedLeadId = this.recordId;
        }

        if (detectedLeadId && detectedLeadId !== this.selectedLeadId) {
            this.selectedLeadId = detectedLeadId;
            this.analysisResult = null;
            this.errorMessage = null;
        }
    }

    handleLeadSelection(event) {
        this.selectedLeadId = event.detail.recordId;
        this.errorMessage = null;
        this.analysisResult = null;
    }

    handleAnalyzeLead() {
        if (!this.selectedLeadId) {
            this.showToast('Error', 'Please select a lead to analyze', 'error');
            return;
        }

        this.isAnalyzing = true;
        this.errorMessage = null;
        this.analysisResult = null;

        analyzeLead({ leadId: this.selectedLeadId })
            .then(result => {
                this.analysisResult = result;
                this.isAnalyzing = false;
                this.showToast('Success', 'Lead analysis completed', 'success');
            })
            .catch(error => {
                this.errorMessage = this.getErrorMessage(error);
                this.isAnalyzing = false;
                this.showToast('Error', this.errorMessage, 'error');
            });
    }

    getErrorMessage(error) {
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        if (typeof error === 'string') return error;
        return 'An unknown error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get scoreClass() {
        if (!this.analysisResult) return 'score-circle';
        const score = this.analysisResult.conversionScore;
        if (score >= 75) return 'score-circle score-high';
        if (score >= 50) return 'score-circle score-medium';
        return 'score-circle score-low';
    }

    get recommendationLabel() {
        if (!this.analysisResult) return '';
        const rec = this.analysisResult.recommendation;
        if (rec === 'YES') return 'RECOMMENDED FOR CONVERSION';
        if (rec === 'NO') return 'NOT RECOMMENDED';
        if (rec === 'MAYBE') return 'NEEDS MORE EVALUATION';
        return rec;
    }

    get recommendationClass() {
        if (!this.analysisResult) return '';
        const rec = this.analysisResult.recommendation;
        if (rec === 'YES') return 'recommendation-yes';
        if (rec === 'NO') return 'recommendation-no';
        if (rec === 'MAYBE') return 'recommendation-maybe';
        return '';
    }

    get hasPositiveSignals() {
        return this.analysisResult?.positiveSignals?.length > 0;
    }

    get hasNegativeSignals() {
        return this.analysisResult?.negativeSignals?.length > 0;
    }

    get hasNextSteps() {
        return this.analysisResult?.nextSteps?.length > 0;
    }

    get hasRiskFactors() {
        return this.analysisResult?.riskFactors?.length > 0;
    }
}