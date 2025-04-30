public with sharing class AdaWalletsSetupCtrl {
    @AuraEnabled
    public static SetupData getSetup() {
        try {
            return new SetupData()                
                .withPrivateKey(AdaWalletsService.getPrivateKey())
                .withBlockfrostProjectId(AdaWalletsService.getBlockfrostProjectId());
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveBlockfrostProjectId(String blockfrostProjectId) {
        try {            
            AdaWalletsService.setBlockfrostProjectId(blockfrostProjectId);
        } catch (Exception e) {            
            throw new AuraHandledException('Failed to save Blockfrost project Id: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static SetupData generatePrivateKey() {
        try {
            String privateKey = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
            AdaWalletsService.setPrivateKey(privateKey);
            return getSetup();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String testBlockfrostConfig() {
        try {
            return BlockfrostService.getBlockfrostConfig();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class SetupData {        
        @AuraEnabled
        public String privateKey { get; set; }
        @AuraEnabled
        public String blockfrostProjectId { get; set; }

        public SetupData withPrivateKey(String value) {
            privateKey = enrich(value);
            return this;
        }

        public SetupData withBlockfrostProjectId(String value) {
            blockfrostProjectId = enrich(value);
            return this;
        }

        private String enrich(String value) {
            return value == null ? '' : value;
        }
    }

    @AuraEnabled
    public static void enableLogging() {
        try {
            new LoggerService().updateLoggerService(true);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void disableLogging() {
        try {
            new LoggerService().updateLoggerService(false);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
