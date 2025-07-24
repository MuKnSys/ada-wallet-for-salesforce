public with sharing class AdaWalletsSetupCtrl {
    @AuraEnabled
    public static SetupData getSetup() {
        try {
            return new SetupData()                
                .withPrivateKey(AdaWalletsService.getPrivateKey())
                .withBlockfrostProjectId(AdaWalletsService.getBlockfrostProjectId())
                .withTransactionApprovalsEnabled(AdaWalletsService.isTransactionApprovalsEnabled())
                .withIsEncryptionKeySet(AdaWalletsService.isEncryptionKeySet())
                .withIsHmacKeySet(AdaWalletsService.isHmacKeySet());
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
    public static SetupData generatePrivateAndHmacKey() {
        try {
            // Check if key is already set (immutable)
            if (AdaWalletsService.isEncryptionKeySet()) {
                throw new AuraHandledException('Encryption key is already set and cannot be changed for security reasons');
            }
            if (AdaWalletsService.isHmacKeySet()) {
                throw new AuraHandledException('Hmac key is already set and cannot be changed for security reasons');
            }
            
            String privateKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
            String hmacKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
            AdaWalletsService.setPrivateKey(privateKey);
            AdaWalletsService.setHmacKey(hmacKey);
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
        @AuraEnabled
        public Boolean isTransactionApprovalsEnabled { get; set; }
        @AuraEnabled
        public Boolean isEncryptionKeySet { get; set; }
        @AuraEnabled
        public Boolean isHmacKeySet { get; set; }

        public SetupData withPrivateKey(String value) {
            privateKey = enrich(value);
            return this;
        }

        public SetupData withBlockfrostProjectId(String value) {
            blockfrostProjectId = value;
            return this;
        }

        public SetupData withTransactionApprovalsEnabled(Boolean value) {
            isTransactionApprovalsEnabled = value;
            return this;
        }
        
        public SetupData withIsEncryptionKeySet(Boolean value) {
            isEncryptionKeySet = value;
            return this;
        }

        public SetupData withIsHmacKeySet(Boolean value) {
            isHmacKeySet = value;
            return this;
        }

        private String enrich(String value) {
            if (String.isBlank(value)) {
                return '';
            }
            return value;
        }
    }

    @AuraEnabled
    public static void enableLogging() {
        try {
            new LoggerServiceADA().updateLoggerService(true);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void disableLogging() {
        try {
            new LoggerServiceADA().updateLoggerService(false);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateTransactionApprovals(Boolean isEnabled) {
        try {
            AdaWalletsService.setTransactionApprovalsEnabled(isEnabled);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update transaction approvals setting: ' + e.getMessage());
        }
    }
}
