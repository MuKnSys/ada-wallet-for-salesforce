public with sharing class EncryptedDataService {
    public static String getEncryptedSeedPhrase(Id recordId) {
        Wallet_Set__c walletSet = WalletSetSelector.getWalletSetWithSeedPhrase(recordId);

        if (!hasAccessToDecrypt()) {
            throw new SecurityException('Access denied to decrypt seed phrase');
        }

        return walletSet.Seed_Phrase__c;
    }

    public static ShowWalletKeysCtrl.WalletKeyWrapper getDecryptedWalletKeys(Id recordId) {
        Wallet__c wallet = WalletSelector.getWalletById(recordId);

        if (!hasAccessToDecrypt()) {
            throw new SecurityException('Access denied to decrypt wallet keys');
        }

        ShowWalletKeysCtrl.WalletKeyWrapper keys = new ShowWalletKeysCtrl.WalletKeyWrapper();            
        keys.privateKey = DataEncryptor.decrypt(wallet.Account_Private_Key__c);
        keys.publicKey  = DataEncryptor.decrypt(wallet.Account_Public_Key__c);

        return keys;
    }

    public static Boolean hasAccessToDecrypt() {        
        try {
            Set<Id> psIds = new Set<Id>();
            for (PermissionSetAssignment psa : [SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId()]) {
                psIds.add(psa.PermissionSetId);
            }
            
            Id requiredPsId = [SELECT Id FROM PermissionSet WHERE Name = 'Ada_Wallet_Seed_Phrase' LIMIT 1].Id;
            
            Boolean hasAccess = requiredPsId != null && psIds.contains(requiredPsId);
            
            return hasAccess;
        } catch (Exception e) {
            return false;
        }
    }
}