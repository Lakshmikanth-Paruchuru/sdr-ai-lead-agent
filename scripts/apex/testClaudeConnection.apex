// Anonymous Apex — verify Named Credential + External Credential + Principal access.
// Developer Console → Debug → Open Execute Anonymous Window
// or: sf apex run --file scripts/apex/testClaudeConnection.apex --target-org <alias>
try {
    String testPrompt = 'Respond with just the word SUCCESS if you receive this message.';
    ClaudeAPIService.ClaudeResponse response = ClaudeAPIService.callClaude(testPrompt);
    System.debug('SUCCESS! Response: ' + response.content);
    System.debug('Model: ' + response.model);
} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
}
