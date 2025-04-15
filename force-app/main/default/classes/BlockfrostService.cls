public with sharing class BlockfrostService {
    private static final String blocksUrl = '/blocks/latest';
    
    public static String getBlockfrostConfig() {
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
            .get()
            .setEndpoint(blocksUrl)
            .setHeaders(
                new Map<String, String>{ 'Project_id' => projectId, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
            )
            .send();

        if (endpoint.getStatusCode() == 200) {
            return endpoint.getResponse().getBody();
        } else {
            throw new BlockfrostEndpoint.BlockfrostAPIException(
                System.Label.AdaWalletsSetup_BlockfrostGetConfigAPIError
            );
        }
    }

    public class BlockfrostPlatformError {
        public Integer code;
        public String message;
    }
}