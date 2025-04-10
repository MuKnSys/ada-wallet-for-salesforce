public with sharing class AdaWalletsSetupCtrl {
    @AuraEnabled
    public static SetupData getSetup() {
        try {
            return new SetupData()                
                .withPrivateKey(AdaWalletsService.getPrivateKey());
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }    

    @AuraEnabled
    public static SetupData generatePrivateKey() {
        try {
            String privateKey = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
            AdaWalletsService.setPrivateKey(privateKey);
            return getSetup();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class SetupData {        
        @AuraEnabled
        public String privateKey { get; set; }        

        public SetupData withPrivateKey(String value) {
            privateKey = enrich(value);
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
