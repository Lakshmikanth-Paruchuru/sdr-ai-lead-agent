/**
 * @description Service class to analyze leads using Claude AI
 * @author SDR Agent Bot
 */
public with sharing class LeadAnalysisService {

    /**
     * @description Analyze a lead and determine conversion potential
     * @param leadId The ID of the lead to analyze
     * @return LeadAnalysisResult containing AI analysis and scoring
     */
    @AuraEnabled
    public static LeadAnalysisResult analyzeLead(String leadId) {
        try {
            // Fetch lead data with related activities
            Lead leadData = getLeadWithActivities(leadId);

            // Fetch email messages
            List<EmailMessage> emailMessages = getEmailMessages(leadData.Email);

            // Get Einstein Score
            Decimal einsteinScore = getEinsteinScore(leadId);

            // Build the prompt for Claude
            String prompt = buildLeadAnalysisPrompt(leadData, emailMessages, einsteinScore);

            // Debug logging to see what data is being analyzed
            System.debug('=== SDR AGENT ANALYSIS ===');
            System.debug('Lead: ' + leadData.Name + ' (' + leadData.Id + ')');
            System.debug('Company: ' + leadData.Company);
            System.debug('Status: ' + leadData.Status + ', Rating: ' + leadData.Rating);
            System.debug('Tasks count: ' + (leadData.Tasks != null ? leadData.Tasks.size() : 0));
            System.debug('Events count: ' + (leadData.Events != null ? leadData.Events.size() : 0));
            System.debug('Email Messages count: ' + emailMessages.size());
            System.debug('Prompt length: ' + prompt.length() + ' characters');

            // Call Claude API
            ClaudeAPIService.ClaudeResponse claudeResponse = ClaudeAPIService.callClaude(prompt);
            
            // Log Claude's raw response
            System.debug('Claude Response: ' + claudeResponse.content);

            // Parse and return the analysis
            LeadAnalysisResult result = parseAnalysisResult(claudeResponse.content, leadData);

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Error analyzing lead: ' + e.getMessage());
        }
    }

    /**
     * @description Fetch lead data with all related activities
     * @param leadId The ID of the lead
     * @return Lead record with related data
     */
    private static Lead getLeadWithActivities(String leadId) {
        List<Lead> leads = [
            SELECT Id, Name, Email, Company, Title, Industry, Status, Rating,
                   LeadSource, Phone, MobilePhone, Website, NumberOfEmployees,
                   AnnualRevenue, Description, CreatedDate,
                   (SELECT Id, Subject, Status, ActivityDate, Description, Type,
                           TaskSubtype, CreatedDate, CompletedDateTime
                    FROM Tasks
                    ORDER BY CreatedDate DESC
                    LIMIT 50),
                   (SELECT Id, Subject, ActivityDate, ActivityDateTime, Description,
                           IsTask, CreatedDate
                    FROM ActivityHistories
                    ORDER BY CreatedDate DESC
                    LIMIT 50),
                   (SELECT Id, Subject, StartDateTime, EndDateTime, Description,
                           Type, CreatedDate
                    FROM Events
                    ORDER BY CreatedDate DESC
                    LIMIT 25)
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        if (leads.isEmpty()) {
            throw new LeadAnalysisException('Lead not found: ' + leadId);
        }

        return leads[0];
    }

    /**
     * @description Fetch email messages related to the lead
     * @param leadEmail The lead's email address
     * @return List of EmailMessage records
     */
    private static List<EmailMessage> getEmailMessages(String leadEmail) {
        if (String.isBlank(leadEmail)) {
            return new List<EmailMessage>();
        }

        return [
            SELECT Id, Subject, TextBody, HtmlBody, FromAddress, ToAddress,
                   Status, MessageDate, Incoming, HasAttachment, CreatedDate
            FROM EmailMessage
            WHERE ToAddress LIKE :('%' + leadEmail + '%')
               OR FromAddress = :leadEmail
            ORDER BY CreatedDate DESC
            LIMIT 30
        ];
    }

    /**
     * @description Get Einstein Lead Score if available
     * @param leadId The lead ID
     * @return Einstein Score or null (returns null if Einstein Lead Scoring is not enabled)
     */
    private static Decimal getEinsteinScore(String leadId) {
        // Einstein Lead Scoring field (PLS_Score__c) is not available in this org
        // Return null - the analysis will proceed without Einstein Score
        return null;
    }

    /**
     * @description Build a comprehensive prompt for Claude to analyze the lead
     * @param lead The lead record with activities
     * @param emailMessages Related email messages
     * @param einsteinScore Einstein Lead Score if available
     * @return Formatted prompt string
     */
    private static String buildLeadAnalysisPrompt(Lead lead, List<EmailMessage> emailMessages, Decimal einsteinScore) {
        List<String> promptParts = new List<String>();

        promptParts.add('You are an expert SDR (Sales Development Representative) AI assistant. ');
        promptParts.add('Analyze the following lead information and determine if this is a potential ');
        promptParts.add('lead that should be converted to an Account/Opportunity.\n\n');

        promptParts.add('## LEAD INFORMATION\n\n');
        promptParts.add('**Name:** ' + lead.Name + '\n');
        promptParts.add('**Company:** ' + (lead.Company != null ? lead.Company : 'N/A') + '\n');
        promptParts.add('**Title:** ' + (lead.Title != null ? lead.Title : 'N/A') + '\n');
        promptParts.add('**Email:** ' + (lead.Email != null ? lead.Email : 'N/A') + '\n');
        promptParts.add('**Phone:** ' + (lead.Phone != null ? lead.Phone : 'N/A') + '\n');
        promptParts.add('**Industry:** ' + (lead.Industry != null ? lead.Industry : 'N/A') + '\n');
        promptParts.add('**Lead Source:** ' + (lead.LeadSource != null ? lead.LeadSource : 'N/A') + '\n');
        promptParts.add('**Current Status:** ' + lead.Status + '\n');
        promptParts.add('**Rating:** ' + (lead.Rating != null ? lead.Rating : 'N/A') + '\n');
        promptParts.add('**Website:** ' + (lead.Website != null ? lead.Website : 'N/A') + '\n');
        promptParts.add('**Employees:** ' + (lead.NumberOfEmployees != null ? String.valueOf(lead.NumberOfEmployees) : 'N/A') + '\n');
        promptParts.add('**Annual Revenue:** ' + (lead.AnnualRevenue != null ? String.valueOf(lead.AnnualRevenue) : 'N/A') + '\n');
        promptParts.add('**Description:** ' + (lead.Description != null ? lead.Description : 'N/A') + '\n');
        promptParts.add('**Created Date:** ' + String.valueOf(lead.CreatedDate) + '\n');

        // Add Einstein Score if available
        if (einsteinScore != null) {
            promptParts.add('**Einstein Lead Score:** ' + String.valueOf(einsteinScore) + '\n');
        }
        promptParts.add('\n');

        // Add email activities
        promptParts.add('## EMAIL & ACTIVITY HISTORY\n\n');

        if (lead.Tasks != null && !lead.Tasks.isEmpty()) {
            promptParts.add('### Recent Tasks and Emails:\n');
            for (Task t : lead.Tasks) {
                promptParts.add('- **' + (t.Subject != null ? t.Subject : 'No Subject') + '**\n');
                promptParts.add('  - Type: ' + (t.Type != null ? t.Type : 'N/A') + '\n');
                promptParts.add('  - Subtype: ' + (t.TaskSubtype != null ? t.TaskSubtype : 'N/A') + '\n');
                promptParts.add('  - Status: ' + t.Status + '\n');
                promptParts.add('  - Date: ' + String.valueOf(t.ActivityDate) + '\n');
                if (t.Description != null) {
                    promptParts.add('  - Details: ' + t.Description + '\n');
                }
                promptParts.add('\n');
            }
        }

        if (lead.Events != null && !lead.Events.isEmpty()) {
            promptParts.add('### Recent Events/Meetings:\n');
            for (Event e : lead.Events) {
                promptParts.add('- **' + (e.Subject != null ? e.Subject : 'No Subject') + '**\n');
                promptParts.add('  - Type: ' + (e.Type != null ? e.Type : 'N/A') + '\n');
                promptParts.add('  - Date: ' + String.valueOf(e.StartDateTime) + '\n');
                if (e.Description != null) {
                    promptParts.add('  - Details: ' + e.Description + '\n');
                }
                promptParts.add('\n');
            }
        }

        if ((lead.Tasks == null || lead.Tasks.isEmpty()) && (lead.Events == null || lead.Events.isEmpty())) {
            promptParts.add('*No tasks or events recorded.*\n\n');
        }

        // Add Email Messages
        if (emailMessages != null && !emailMessages.isEmpty()) {
            promptParts.add('### Email Messages:\n');
            for (EmailMessage em : emailMessages) {
                promptParts.add('- **' + (em.Subject != null ? em.Subject : 'No Subject') + '**\n');
                promptParts.add('  - Direction: ' + (em.Incoming ? 'Incoming' : 'Outgoing') + '\n');
                promptParts.add('  - From: ' + (em.FromAddress != null ? em.FromAddress : 'N/A') + '\n');
                promptParts.add('  - To: ' + (em.ToAddress != null ? em.ToAddress : 'N/A') + '\n');
                promptParts.add('  - Date: ' + String.valueOf(em.MessageDate) + '\n');
                promptParts.add('  - Status: ' + (em.Status != null ? em.Status : 'N/A') + '\n');
                if (em.TextBody != null && em.TextBody.length() > 0) {
                    String emailBody = em.TextBody.length() > 500 ? em.TextBody.substring(0, 500) + '...' : em.TextBody;
                    promptParts.add('  - Content Preview: ' + emailBody + '\n');
                }
                promptParts.add('\n');
            }
        } else {
            promptParts.add('### Email Messages:\n');
            promptParts.add('*No email messages found.*\n\n');
        }

        promptParts.add('## ANALYSIS REQUEST\n\n');
        promptParts.add('Based on the above information, provide:\n\n');
        promptParts.add('1. **Conversion Score** (0-100): A numerical score indicating conversion potential\n');
        promptParts.add('2. **Conversion Recommendation**: Should this lead be converted? (YES/NO/MAYBE)\n');
        promptParts.add('3. **Key Signals**: List the positive and negative signals you identified\n');
        promptParts.add('4. **Engagement Analysis**: Analyze the email activity patterns and engagement level\n');
        promptParts.add('5. **Next Steps**: Recommend specific actions the SDR should take\n');
        promptParts.add('6. **Risk Factors**: Any concerns or red flags\n\n');
        promptParts.add('Format your response as JSON with the following structure:\n');
        promptParts.add('{\n');
        promptParts.add('  "conversionScore": <number 0-100>,\n');
        promptParts.add('  "recommendation": "<YES|NO|MAYBE>",\n');
        promptParts.add('  "positiveSignals": ["signal1", "signal2"],\n');
        promptParts.add('  "negativeSignals": ["signal1", "signal2"],\n');
        promptParts.add('  "engagementLevel": "<HIGH|MEDIUM|LOW>",\n');
        promptParts.add('  "engagementAnalysis": "<detailed analysis>",\n');
        promptParts.add('  "nextSteps": ["step1", "step2"],\n');
        promptParts.add('  "riskFactors": ["risk1", "risk2"],\n');
        promptParts.add('  "summary": "<brief summary of the analysis>"\n');
        promptParts.add('}');

        return String.join(promptParts, '');
    }

    /**
     * @description Parse Claude's response into structured result
     * @param claudeContent The content from Claude API
     * @param lead The original lead record
     * @return LeadAnalysisResult
     */
    private static LeadAnalysisResult parseAnalysisResult(String claudeContent, Lead lead) {
        LeadAnalysisResult result = new LeadAnalysisResult();
        result.leadId = lead.Id;
        result.leadName = lead.Name;
        result.company = lead.Company;

        try {
            // Extract JSON from Claude's response (it might have markdown formatting)
            String jsonContent = extractJSON(claudeContent);

            Map<String, Object> analysis = (Map<String, Object>) JSON.deserializeUntyped(jsonContent);

            result.conversionScore = analysis.get('conversionScore') != null ?
                Integer.valueOf(analysis.get('conversionScore')) : 0;
            result.recommendation = (String) analysis.get('recommendation');
            result.engagementLevel = (String) analysis.get('engagementLevel');
            result.engagementAnalysis = (String) analysis.get('engagementAnalysis');
            result.summary = (String) analysis.get('summary');

            result.positiveSignals = convertToStringList((List<Object>) analysis.get('positiveSignals'));
            result.negativeSignals = convertToStringList((List<Object>) analysis.get('negativeSignals'));
            result.nextSteps = convertToStringList((List<Object>) analysis.get('nextSteps'));
            result.riskFactors = convertToStringList((List<Object>) analysis.get('riskFactors'));

            result.rawResponse = claudeContent;

        } catch (Exception e) {
            result.conversionScore = 0;
            result.recommendation = 'ERROR';
            result.summary = 'Failed to parse AI response: ' + e.getMessage();
            result.rawResponse = claudeContent;
        }

        return result;
    }

    /**
     * @description Extract JSON from Claude's response (remove markdown formatting)
     * @param content The raw content
     * @return Clean JSON string
     */
    private static String extractJSON(String content) {
        if (content.contains('```json')) {
            Integer startIdx = content.indexOf('```json') + 7;
            Integer endIdx = content.indexOf('```', startIdx);
            return content.substring(startIdx, endIdx).trim();
        } else if (content.contains('```')) {
            Integer startIdx = content.indexOf('```') + 3;
            Integer endIdx = content.indexOf('```', startIdx);
            return content.substring(startIdx, endIdx).trim();
        }
        return content.trim();
    }

    /**
     * @description Convert List<Object> to List<String>
     */
    private static List<String> convertToStringList(List<Object> objList) {
        List<String> stringList = new List<String>();
        if (objList != null) {
            for (Object obj : objList) {
                stringList.add(String.valueOf(obj));
            }
        }
        return stringList;
    }

    /**
     * @description Wrapper class for lead analysis results
     */
    public class LeadAnalysisResult {
        @AuraEnabled public String leadId { get; set; }
        @AuraEnabled public String leadName { get; set; }
        @AuraEnabled public String company { get; set; }
        @AuraEnabled public Integer conversionScore { get; set; }
        @AuraEnabled public String recommendation { get; set; }
        @AuraEnabled public String engagementLevel { get; set; }
        @AuraEnabled public String engagementAnalysis { get; set; }
        @AuraEnabled public String summary { get; set; }
        @AuraEnabled public List<String> positiveSignals { get; set; }
        @AuraEnabled public List<String> negativeSignals { get; set; }
        @AuraEnabled public List<String> nextSteps { get; set; }
        @AuraEnabled public List<String> riskFactors { get; set; }
        @AuraEnabled public String rawResponse { get; set; }
    }

    /**
     * @description Custom exception
     */
    public class LeadAnalysisException extends Exception {}
}