// File: force-app/main/default/classes/ShowWalletKeysCtrl.cls
public with sharing class ShowWalletKeysCtrl {
    /**
     * Wrapper to hold both decrypted keys.
     */
    public class WalletKeyWrapper {
        @AuraEnabled public String privateKey { get; set; }
        @AuraEnabled public String publicKey  { get; set; }
    }

    /**
     * Retrieves and decrypts both the private and public keys for a given Wallet__c.
     */
    @AuraEnabled
    public static WalletKeyWrapper getWalletKeys(Id walletId) {
        try {
            Wallet__c wallet = WalletSelector.getWalletById(walletId);
            Logger.logInfo(
                'Wallet Keys was retrieved by ' + UserInfo.getName() +
                ' (Id: ' + UserInfo.getUserId() + ') for Wallet with ID: ' + wallet.Id
            );

            WalletKeyWrapper keys = new WalletKeyWrapper();
            // Use the correct API names for your custom fields:
            keys.privateKey = DataEncryptor.decrypt(wallet.Account_Private_Key__c);
            keys.publicKey  = DataEncryptor.decrypt(wallet.Account_Public_Key__c);

            return keys;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving Wallet Keys: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }
}
