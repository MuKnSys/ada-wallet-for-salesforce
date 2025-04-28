// File: force-app/main/default/classes/ShowWalletKeysCtrl.cls
public with sharing class ShowWalletKeysCtrl {
    /**
     * Wrapper to hold both decrypted keys.
     */
    public class WalletKeyWrapper {
        @AuraEnabled public String privateKey { get; set; }
        @AuraEnabled public String publicKey  { get; set; }
    }
    
    @AuraEnabled
    public static WalletKeyWrapper getWalletKeys(Id walletId) {
        try {
            WalletKeyWrapper keys = EncryptedDataService.getDecryptedWalletKeys(walletId);            
            Logger.logInfo(
                'Wallet Keys was retrieved by ' + UserInfo.getName() +
                ' (Id: ' + UserInfo.getUserId() + ') for Wallet with ID: ' + walletId
            );
            return keys;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving Wallet Keys: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }
}
