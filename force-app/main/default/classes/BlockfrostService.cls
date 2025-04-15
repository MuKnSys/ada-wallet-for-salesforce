public with sharing class BlockfrostService {
    private static final String blocksUrl = '/blocks/latest';

    @AuraEnabled
    public static String getBlockfrostConfig() {
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
            .get()
            .setEndpoint(blocksUrl)
            .setHeaders(
                new Map<String, String>{ 'Project_id' => projectId }
            )
            .send();

        if (endpoint.getStatusCode() == 200) {
            return endpoint.getResponse().getBody();
        } else {
            throw new BlockfrostEndpoint.BlockfrostAPIException(
                System.Label.AdaWalletsSetup_BlockfrostGetConfigAPIError + getErrorMessage(endpoint.getResponse().getBody())
            );
        }
    }

    public static String getErrorMessage(String errorMessage) {
        BlockfrostPlatformError errors = (BlockfrostPlatformError) JSON.deserialize(errorMessage, BlockfrostPlatformError.class);
        return ' ' + errors.message;
    }

    public class BlockfrostPlatformError {
        public Integer code;
        public String message;
    }
}