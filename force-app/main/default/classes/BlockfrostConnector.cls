public with sharing class BlockfrostConnector {
    @AuraEnabled
    public static String testBlockfrostConfig() {
        try {            
            String projectId = AdaWalletsService.getBlockfrostProjectId();            
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint('https://cardano-mainnet.blockfrost.io/api/v0/blocks/latest');
            request.setMethod('GET');
            request.setHeader('project_id', projectId);
            request.setTimeout(120000); // 2 minutes timeout

            HttpResponse response = http.send(request);
            if (response.getStatusCode() == 200) {
                return response.getBody(); // Return raw JSON response
            } else {
                throw new AuraHandledException('API Call Failed: ' + response.getStatus() + ' - ' + response.getBody());
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error testing Blockfrost config: ' + e.getMessage());
        }
    }
}