public with sharing class UTXOAddressSelector {
    
    // Wrapper class to hold UTXO address with decrypted private key
    public class UTXOAddressWithDecryptedKey {
        public UTXO_Address__c utxoAddress;
        public String decryptedPrivateKey;
        
        public UTXOAddressWithDecryptedKey(UTXO_Address__c addr, String decryptedKey) {
            this.utxoAddress = addr;
            this.decryptedPrivateKey = decryptedKey;
        }
    }
    
    public static List<UTXO_Address__c> getUTXOAddressesByWalletId(Id walletId, Set<String> types) {
        String query = 'SELECT Id, Name, Address__c, Is_Used__c, Public_Key__c, Path__c, Staking_Key_Hash__c, Index__c, Type__c, Private_Key__c' + 
            ' FROM UTXO_Address__c' +
            ' WHERE Wallet__c = :walletId';
            
        if (types != null && !types.isEmpty()) {
            query += ' AND Type__c IN :types';
        }
        
        query += ' WITH SECURITY_ENFORCED ORDER BY Name ASC';
        System.debug('UTXOAddressSelector.getUTXOAddressesByWalletId query: ' + query);
        return Database.query(query);
    }

    public static List<UTXO_Address__c> getLastUTXOAddressByType(Id walletId, String type) {
        return [
            SELECT Id, Name, Address__c, Public_Key__c, Path__c, Staking_Key_Hash__c, Index__c, Type__c, Private_Key__c
            FROM UTXO_Address__c
            WHERE Wallet__c = :walletId
            AND Type__c = :type
            WITH SECURITY_ENFORCED
            ORDER BY Index__c DESC
            LIMIT 1
        ];
    }

    public static List<UTXO_Address__c> getUTXOAddressesByWalletIdAndTypeOrdered(Id walletId, String type) {
        return [
            SELECT Id, Name, Address__c, Public_Key__c, Path__c, Staking_Key_Hash__c, Index__c, Type__c, Private_Key__c
            FROM UTXO_Address__c
            WHERE Wallet__c = :walletId
            AND Type__c = :type
            WITH SECURITY_ENFORCED
            ORDER BY Index__c ASC
        ];
    }
    
    // New methods that decrypt private keys directly
    
    @AuraEnabled
    public static List<UTXOAddressWithDecryptedKey> getUTXOAddressesWithDecryptedKeysByWalletId(Id walletId, List<String> types) {
        try {
            // Check if user has permission to decrypt private keys
            if (!EncryptedDataService.hasAccessToDecrypt()) {
                throw new AuraHandledException('Access denied to decrypt private keys. You need the "Ada_Wallet_Seed_Phrase" permission set.');
            }
            
            // Convert List<String> to Set<String> for the existing method
            Set<String> typesSet = types != null ? new Set<String>(types) : null;
            List<UTXO_Address__c> addresses = getUTXOAddressesByWalletId(walletId, typesSet);
            List<UTXOAddressWithDecryptedKey> result = new List<UTXOAddressWithDecryptedKey>();
            
            for (UTXO_Address__c addr : addresses) {
                String decryptedKey = null;
                if (String.isNotBlank(addr.Private_Key__c)) {
                    try {
                        decryptedKey = DataEncryptor.decrypt(addr.Private_Key__c);
                    } catch (Exception e) {
                        System.debug('Failed to decrypt private key for address ' + addr.Id + ': ' + e.getMessage());
                        // Continue with null decrypted key
                    }
                }
                result.add(new UTXOAddressWithDecryptedKey(addr, decryptedKey));
            }
            
            return result;
        } catch (Exception e) {
            Logger.logError('Error in getUTXOAddressesWithDecryptedKeysByWalletId: ' + e.getMessage());
            throw new AuraHandledException('Error fetching UTXO addresses with decrypted keys: ' + e.getMessage());
        }
    }
    
    // Method to get a single UTXO address with decrypted private key by ID
    @AuraEnabled
    public static UTXOAddressWithDecryptedKey getUTXOAddressWithDecryptedKeyById(Id utxoAddressId) {
        try {
            // Check if user has permission to decrypt private keys
            if (!EncryptedDataService.hasAccessToDecrypt()) {
                throw new AuraHandledException('Access denied to decrypt private keys. You need the "Ada_Wallet_Seed_Phrase" permission set.');
            }
            
            UTXO_Address__c addr = [
                SELECT Id, Name, Address__c, Public_Key__c, Path__c, Staking_Key_Hash__c, Index__c, Type__c, Private_Key__c
                FROM UTXO_Address__c
                WHERE Id = :utxoAddressId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            String decryptedKey = null;
            if (String.isNotBlank(addr.Private_Key__c)) {
                try {
                    decryptedKey = DataEncryptor.decrypt(addr.Private_Key__c);
                } catch (Exception e) {
                    System.debug('Failed to decrypt private key for address ' + addr.Id + ': ' + e.getMessage());
                    // Continue with null decrypted key
                }
            }
            
            return new UTXOAddressWithDecryptedKey(addr, decryptedKey);
        } catch (Exception e) {
            Logger.logError('Error in getUTXOAddressWithDecryptedKeyById: ' + e.getMessage());
            throw new AuraHandledException('Error fetching UTXO address with decrypted key: ' + e.getMessage());
        }
    }
} 