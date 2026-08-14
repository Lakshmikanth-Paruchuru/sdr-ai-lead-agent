/**
 * @description Service class to integrate with Claude AI API
 * @author SDR Agent Bot
 * /*
 * // Test Claude API Connection
try {
    String testPrompt = 'Respond with just the word SUCCESS if you receive this message.';
 
    ClaudeAPIService.ClaudeResponse response = ClaudeAPIService.callClaude(testPrompt);
 
    System.debug('SUCCESS! Response: ' + response.content);
    System.debug('Model: ' + response.model);
 
} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
}
*/
public with sharing class ClaudeAPIService {

    private static final String CLAUDE_API_ENDPOINT = 'callout:Claude_API/v1/messages';
    private static final String CLAUDE_MODEL = 'claude-sonnet-4-5-20250929';
    private static final Integer MAX_TOKENS = 4096;

    /**
     * @description Call Claude API with a prompt
     * @param prompt The prompt to send to Claude
     * @return ClaudeResponse wrapper containing the AI response
     */
    public static ClaudeResponse callClaude(String prompt) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(CLAUDE_API_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('anthropic-version', '2023-06-01');

            // Build request body
            Map<String, Object> requestBody = new Map<String, Object>{
                'model' => CLAUDE_MODEL,
                'max_tokens' => MAX_TOKENS,
                'messages' => new List<Map<String, String>>{
                    new Map<String, String>{
                        'role' => 'user',
                        'content' => prompt
                    }
                }
            };

            req.setBody(JSON.serialize(requestBody));
            req.setTimeout(120000); // 120 second timeout

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                return parseClaudeResponse(res.getBody());
            } else {
                throw new ClaudeAPIException('API Error: ' + res.getStatusCode() + ' - ' + res.getBody());
            }

        } catch (Exception e) {
            throw new ClaudeAPIException('Failed to call Claude API: ' + e.getMessage());
        }
    }

    /**
     * @description Parse Claude API response
     * @param responseBody JSON response from Claude API
     * @return ClaudeResponse wrapper
     */
    private static ClaudeResponse parseClaudeResponse(String responseBody) {
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> content = (List<Object>) responseMap.get('content');

        String textContent = '';
        if (content != null && !content.isEmpty()) {
            Map<String, Object> contentBlock = (Map<String, Object>) content[0];
            textContent = (String) contentBlock.get('text');
        }

        ClaudeResponse response = new ClaudeResponse();
        response.content = textContent;
        response.model = (String) responseMap.get('model');
        response.stopReason = (String) responseMap.get('stop_reason');

        return response;
    }

    /**
     * @description Wrapper class for Claude API response
     */
    public class ClaudeResponse {
        public String content { get; set; }
        public String model { get; set; }
        public String stopReason { get; set; }
    }

    /**
     * @description Custom exception for Claude API errors
     */
    public class ClaudeAPIException extends Exception {}
}