public with sharing class EncryptedDataService {
    public static String getDecryptedSeedPhrase(Id recordId) {
        Wallet_Set__c walletSet = WalletSetSelector.getWalletSetById(recordId);

        if (!hasAccessToDecrypt()) {
            throw new SecurityException('Access denied to decrypt seed phrase');
        }

        return DataEncryptor.decrypt(walletSet.Seed_Phrase__c);
    }

    private static Boolean hasAccessToDecrypt() {        
        Set<Id> psIds = new Set<Id>();
        for (PermissionSetAssignment psa : [SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId()]) {
            psIds.add(psa.PermissionSetId);
        }
        
        Id requiredPsId = [SELECT Id FROM PermissionSet WHERE Name = 'EncryptedDataAccess' LIMIT 1].Id;

        return psIds.contains(requiredPsId);
    }
}