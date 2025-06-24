public with sharing class UTXOController {
    // Base-64 placeholder icon for ADA (replace with actual as needed)
    private static final String ADA_ICON_BASE64 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADAAAAAo...';

    public class UTXOAddress {
        @AuraEnabled public Integer index { get; set; }
        @AuraEnabled public String publicKey { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String stakingKeyHash { get; set; }
        @AuraEnabled public String path { get; set; }
        @AuraEnabled public String stakePath { get; set; }
    }

    public class TransactionWrapper {
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String txHash { get; set; }
        @AuraEnabled public Datetime receivedAt { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static String getDecryptedSeedPhrase(Id walletSetId) {
        try {            
            return EncryptedDataService.getDecryptedSeedPhrase(walletSetId);
        } catch (Exception e) {            
            throw new AuraHandledException('Failed to get seed phrase: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Wallet__c getWallet(String walletId) {
        try {
            return WalletSelector.getWalletById(walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void createUTXOAddresses(String walletId, List<UTXOAddress> receivingAddresses, List<UTXOAddress> changeAddresses) {
        try {
            if (receivingAddresses == null || changeAddresses == null) {
                throw new AuraHandledException('Address lists cannot be null');
            }

            // Prepare UTXO_Address__c records
            List<UTXO_Address__c> utxoRecords = new List<UTXO_Address__c>();

            // Process receiving addresses (Type__c = 0)
            for (UTXOAddress addr : receivingAddresses) {
                if (addr.index == null || String.isBlank(addr.address) || String.isBlank(addr.publicKey) || String.isBlank(addr.stakingKeyHash) || String.isBlank(addr.path)) {
                    throw new AuraHandledException('Invalid receiving address data for index ' + addr.index);
                }
                utxoRecords.add(new UTXO_Address__c(
                    Wallet__c = walletId,
                    Address__c = addr.address,
                    Index__c = addr.index,
                    Public_Key__c = addr.publicKey,
                    Staking_Key_Hash__c = addr.stakingKeyHash,
                    Path__c = addr.path,
                    Type__c = '0' // Receiving address
                ));
            }

            // Process change addresses (Type__c = 1)
            for (UTXOAddress addr : changeAddresses) {
                if (addr.index == null || String.isBlank(addr.address) || String.isBlank(addr.publicKey) || String.isBlank(addr.stakingKeyHash) || String.isBlank(addr.path)) {
                    throw new AuraHandledException('Invalid change address data for index ' + addr.index);
                }
                utxoRecords.add(new UTXO_Address__c(
                    Wallet__c = walletId,
                    Address__c = addr.address,
                    Index__c = addr.index,
                    Public_Key__c = addr.publicKey,
                    Staking_Key_Hash__c = addr.stakingKeyHash,
                    Path__c = addr.path,
                    Type__c = '1' // Change address
                ));
            }

            // Insert records with security enforcement
            if (!utxoRecords.isEmpty()) {
                SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, utxoRecords);
                insert decision.getRecords();
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error creating UTxO addresses: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getUTXOAddresses(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            return UTXOAddressSelector.getUTXOAddressesByWalletId(walletId, null);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO addresses: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getUserPermissions() {
        try {
            List<String> assignedPermissionSets = new List<String>();
            for (PermissionSetAssignment psa : [
                SELECT PermissionSet.Name
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()
                WITH SECURITY_ENFORCED
            ]) {
                assignedPermissionSets.add(psa.PermissionSet.Name);
            }
            return assignedPermissionSets;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving user permissions: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Integer getNextUTXOIndex(String walletId, String type) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (String.isBlank(type) || !(type == '0' || type == '1')) {
                throw new AuraHandledException('Type must be "0" (receiving) or "1" (change)');
            }

            // Query UTXO_Address__c records for the given Wallet__c and Type__c
            List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getLastUTXOAddressByType(walletId, type);

            // If no records are found, start at index 0
            if (utxoAddresses.isEmpty()) {
                return 0;
            }

            // Get the highest Index__c and return the next index
            Integer highestIndex = (Integer)utxoAddresses[0].Index__c;
            Integer nextIndex = highestIndex + 1;
            return nextIndex;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving next UTXO index: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void addReceivingUTXOAddress(String walletId, UTXOAddress receivingAddress) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (receivingAddress == null) {
                throw new AuraHandledException('Receiving address cannot be null');
            }
            if (receivingAddress.index == null || String.isBlank(receivingAddress.address) || 
                String.isBlank(receivingAddress.publicKey) || String.isBlank(receivingAddress.stakingKeyHash) || 
                String.isBlank(receivingAddress.path)) {
                throw new AuraHandledException('Invalid receiving address data for index ' + receivingAddress.index);
            }

            // Create a new UTXO_Address__c record for the receiving address (Type__c = 0)
            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = receivingAddress.address,
                Index__c = receivingAddress.index,
                Public_Key__c = receivingAddress.publicKey,
                Staking_Key_Hash__c = receivingAddress.stakingKeyHash,
                Path__c = receivingAddress.path,
                Type__c = '0' // Receiving address
            );

            // Insert the record with security enforcement
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<UTXO_Address__c>{utxoRecord});
            insert decision.getRecords();
        } catch (Exception e) {
            throw new AuraHandledException('Error adding receiving UTXO address: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void addChangeUTXOAddress(String walletId, UTXOAddress changeAddress) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (changeAddress == null) {
                throw new AuraHandledException('Change address cannot be null');
            }
            if (changeAddress.index == null || String.isBlank(changeAddress.address) || 
                String.isBlank(changeAddress.publicKey) || String.isBlank(changeAddress.stakingKeyHash) || 
                String.isBlank(changeAddress.path)) {
                throw new AuraHandledException('Invalid change address data for index ' + changeAddress.index);
            }

            // Create a new UTXO_Address__c record for the change address (Type__c = 1)
            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = changeAddress.address,
                Index__c = changeAddress.index,
                Public_Key__c = changeAddress.publicKey,
                Staking_Key_Hash__c = changeAddress.stakingKeyHash,
                Path__c = changeAddress.path,
                Type__c = '1' // Change address
            );

            // Insert the record with security enforcement
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<UTXO_Address__c>{utxoRecord});
            insert decision.getRecords();
        } catch (Exception e) {
            throw new AuraHandledException('Error adding change UTXO address: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TransactionWrapper> getReceivedTransactions(String walletId) {
        // Placeholder implementation – this can be extended to fetch real data later.
        // For now, simply return an empty list so that the front-end can call the method successfully.
        return new List<TransactionWrapper>();
    }

    @AuraEnabled(cacheable=true)
    public static Integer getUTXOAddressCountWithAssets(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }

            String soql = 'SELECT COUNT() FROM UTXO_Address__c WHERE Wallet__c = :walletId AND Id IN (SELECT UTXO_Address__c FROM UTXO_Asset__c WHERE UTXO_Address__c != NULL)';
            Integer cnt = Database.countQuery(soql);
            return cnt;
        } catch (Exception e) {
            throw new AuraHandledException('Error counting UTXO addresses with assets: ' + e.getMessage());
        }
    }

    public class TokenCount {
        @AuraEnabled public String symbol;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String icon;
    }

    public class AssetTokenSummary {
        @AuraEnabled public Decimal ada;
        @AuraEnabled public List<TokenCount> tokens;
        @AuraEnabled public String adaIcon;
    }

    @AuraEnabled(cacheable=true)
    public static AssetTokenSummary getAssetTokenSummary(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }

            List<AggregateResult> results = [
                SELECT Asset__r.Name name, SUM(Amount__c) total
                FROM UTXO_Asset__c
                WHERE UTXO_Address__r.Wallet__c = :walletId
                GROUP BY Asset__r.Name
            ];

            AssetTokenSummary summary = new AssetTokenSummary();
            summary.ada = 0;
            summary.tokens = new List<TokenCount>();

            for (AggregateResult ar : results) {
                String sym = (String) ar.get('name');
                Decimal c = (Decimal) ar.get('total');
                if (sym == 'ADA') {
                    summary.ada = (Decimal) c;
                } else {
                    TokenCount tc = new TokenCount();
                    tc.symbol = sym;
                    tc.amount = (Decimal) c;
                    summary.tokens.add(tc);
                }
            }

            // Fetch icons for tokens
            Map<String, TokenCount> tokenMap = new Map<String, TokenCount>();
            for (TokenCount tc : summary.tokens) {
                tokenMap.put(tc.symbol, tc);
            }

            // Fetch icons from UTXO_Asset__c records
            for (TokenCount tc : tokenMap.values()) {
                List<UTXO_Asset__c> rows = [SELECT Icon__c FROM UTXO_Asset__c WHERE Blockfrost_ID__c LIKE :tc.symbol+'%' LIMIT 1];
                if (!rows.isEmpty() && rows[0].Icon__c != null) tc.icon = rows[0].Icon__c;
                summary.tokens.add(tc);
            }

            // fetch ADA icon if present (cannot filter on long text in WHERE)
            List<UTXO_Asset__c> adaRows = [SELECT Icon__c FROM UTXO_Asset__c WHERE Blockfrost_ID__c LIKE 'lovelace:%' LIMIT 1];
            if (!adaRows.isEmpty() && adaRows[0].Icon__c != null) summary.adaIcon = adaRows[0].Icon__c;

            return summary;
        } catch (Exception e) {
            throw new AuraHandledException('Error building asset summary: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static AssetTokenSummary getAssetTokenSummaryNoCache(String walletId) {
        // Wrapper to bypass Lightning Data Service cache
        return getAssetTokenSummary(walletId);
    }

    @AuraEnabled(cacheable=false)
    public static String getAddressExtended(Id utxoAddressId) {
        try {
            if (utxoAddressId == null) {
                throw new AuraHandledException('UTXO Address Id cannot be null');
            }
            UTXO_Address__c addr = [SELECT Address__c FROM UTXO_Address__c WHERE Id = :utxoAddressId LIMIT 1];
            if (addr == null || String.isBlank(addr.Address__c)) {
                throw new AuraHandledException('UTXO Address not found or missing Address value');
            }
            return BlockfrostService.getAddressExtended(addr.Address__c);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to retrieve address extended info: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Decimal syncADAAsset(Id utxoAddressId) {
        try {
            if (utxoAddressId == null) {
                throw new AuraHandledException('UTXO Address Id cannot be null');
            }

            // Fetch address value
            UTXO_Address__c addrRec = [SELECT Address__c FROM UTXO_Address__c WHERE Id = :utxoAddressId LIMIT 1];
            if (addrRec == null || String.isBlank(addrRec.Address__c)) {
                throw new AuraHandledException('UTXO Address not found or missing Address__c');
            }

            // Call Blockfrost utxos endpoint
            String utxoJson = BlockfrostService.getAddressUtxos(addrRec.Address__c);
            List<Object> utxoList = (List<Object>) JSON.deserializeUntyped(utxoJson);

            Decimal lovelaceQty = 0;
            for (Object recObj : utxoList) {
                Map<String,Object> rec = (Map<String,Object>) recObj;
                List<Object> amounts = (List<Object>) rec.get('amount');
                for (Object amtObj : amounts) {
                    Map<String,Object> amt = (Map<String,Object>) amtObj;
                    if (String.valueOf(amt.get('unit')) == 'lovelace') {
                        lovelaceQty += Decimal.valueOf(String.valueOf(amt.get('quantity')));
                    }
                }
            }

            Decimal adaAmount = lovelaceQty / 1000000;

            // Get ADA Asset__c Id
            Asset__c adaAsset = [SELECT Id FROM Asset__c WHERE Name = 'ADA' LIMIT 1];

            // Query existing UTXO_Asset__c by Blockfrost ID
            List<UTXO_Asset__c> existing = [SELECT Id, Amount__c, Blockfrost_ID__c FROM UTXO_Asset__c WHERE UTXO_Address__c = :utxoAddressId AND Blockfrost_ID__c = 'lovelace' LIMIT 1];

            if (adaAmount == 0) {
                if (!existing.isEmpty()) {
                    delete existing;
                }
            } else {
                if (existing.isEmpty()) {
                    UTXO_Asset__c newRec = new UTXO_Asset__c(
                        UTXO_Address__c = utxoAddressId,
                        Asset__c = adaAsset.Id,
                        Amount__c = adaAmount,
                        Blockfrost_ID__c = 'lovelace'
                    );
                    insert newRec;
                } else {
                    UTXO_Asset__c rec = existing[0];
                    rec.Amount__c = adaAmount;
                    rec.Blockfrost_ID__c = 'lovelace';
                    update rec;
                }
            }
            return adaAmount;
        } catch (Exception e) {
            throw new AuraHandledException('Error syncing ADA asset: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getFirstUnusedReceivingAddress(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            List<UTXO_Address__c> addrs = [
                SELECT Address__c, Index__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId AND Type__c = '0' AND Id NOT IN (
                    SELECT UTXO_Address__c FROM UTXO_Asset__c WHERE UTXO_Address__c != NULL
                )
                ORDER BY Index__c
                LIMIT 1
            ];
            if (addrs.isEmpty()) {
                return null;
            }
            return addrs[0].Address__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching unused receiving address: ' + e.getMessage());
        }
    }

    private static Decimal getAdaAmountFromUtxos(String address) {
        String utxoJson = BlockfrostService.getAddressUtxos(address);
        List<Object> utxoList = (List<Object>) JSON.deserializeUntyped(utxoJson);
        Decimal lovelaceQty = 0;
        for (Object recObj : utxoList) {
            Map<String,Object> rec = (Map<String,Object>) recObj;
            List<Object> amounts = (List<Object>) rec.get('amount');
            for (Object amtObj : amounts) {
                Map<String,Object> amt = (Map<String,Object>) amtObj;
                if (String.valueOf(amt.get('unit')) == 'lovelace') {
                    lovelaceQty += Decimal.valueOf(String.valueOf(amt.get('quantity')));
                }
            }
        }
        return lovelaceQty / 1000000;
    }

    @AuraEnabled
    public static void syncADAAssetsForWallet(Id walletId) {
        try {
            if (walletId == null) {
                throw new AuraHandledException('Wallet Id cannot be null');
            }
            Asset__c adaAsset = [SELECT Id FROM Asset__c WHERE Name = 'ADA' LIMIT 1];
            List<UTXO_Address__c> addrs = [SELECT Id, Address__c FROM UTXO_Address__c WHERE Wallet__c = :walletId];

            Map<Id, Decimal> addressToAda = new Map<Id, Decimal>();
            for (UTXO_Address__c a : addrs) {
                Decimal amt = 0;
                if (BlockfrostService.hasUtxos(a.Address__c)) {
                    amt = getAdaAmountFromUtxos(a.Address__c);
                }
                addressToAda.put(a.Id, amt);
            }

            Map<Id, UTXO_Asset__c> existingMap = new Map<Id, UTXO_Asset__c>();
            for (UTXO_Asset__c ua : [SELECT Id, UTXO_Address__c, Amount__c, Icon__c FROM UTXO_Asset__c WHERE UTXO_Address__c IN :addrs AND Blockfrost_ID__c = 'lovelace']) {
                existingMap.put(ua.UTXO_Address__c, ua);
            }

            List<UTXO_Asset__c> inserts = new List<UTXO_Asset__c>();
            List<UTXO_Asset__c> updates = new List<UTXO_Asset__c>();
            List<UTXO_Asset__c> deletes = new List<UTXO_Asset__c>();

            for (Id addrId : addressToAda.keySet()) {
                Decimal amt = addressToAda.get(addrId);
                if (existingMap.containsKey(addrId)) {
                    UTXO_Asset__c rec = existingMap.get(addrId);
                    if (amt == 0) {
                        deletes.add(rec);
                    } else {
                        rec.Amount__c = amt;
                        updates.add(rec);
                    }
                } else if (amt > 0) {
                    inserts.add(new UTXO_Asset__c(UTXO_Address__c = addrId, Asset__c = adaAsset.Id, Amount__c = amt, Blockfrost_ID__c='lovelace', Icon__c=null));
                }
            }

            List<UTXO_Asset__c> upserts1 = new List<UTXO_Asset__c>();
            upserts1.addAll(inserts);
            upserts1.addAll(updates);
            if (!upserts1.isEmpty()) upsert upserts1 Blockfrost_ID__c;
            if (!deletes.isEmpty()) delete deletes;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to sync ADA assets for wallet: '+e.getMessage());
        }
    }

    private static Id getAssetId(String unit, String metadataJson) {
        String symbol;
        if (metadataJson != null && metadataJson != '{}') {
            Map<String,Object> metaMap = (Map<String,Object>) JSON.deserializeUntyped(metadataJson);
            if (metaMap.containsKey('metadata')) {
                Map<String,Object> meta = (Map<String,Object>) metaMap.get('metadata');
                if (meta.containsKey('ticker')) {
                    symbol = String.valueOf(meta.get('ticker')).toUpperCase();
                } else if (meta.containsKey('name')) {
                    symbol = String.valueOf(meta.get('name')).toUpperCase();
                }
            }
        }
        if (String.isBlank(symbol)) {
            symbol = unit;
        }

        Asset__c existing = null;
        List<Asset__c> lst = [SELECT Id FROM Asset__c WHERE Name = :symbol LIMIT 1];
        if (!lst.isEmpty()) existing = lst[0];
        if (existing != null) return existing.Id;
        Asset__c newA = new Asset__c(Name=symbol, Asset_Name__c=symbol);
        insert newA;
        return newA.Id;
    }

    @AuraEnabled
    public static void syncAssetsForWallet(Id walletId) {
        try {
            if (walletId == null) throw new AuraHandledException('Wallet Id cannot be null');

            List<UTXO_Address__c> addrs = [SELECT Id, Address__c FROM UTXO_Address__c WHERE Wallet__c = :walletId];

            Map<String, Map<Id, Decimal>> unitAddrQty = new Map<String, Map<Id, Decimal>>();
            Set<String> units = new Set<String>();

            // Callouts first
            for (UTXO_Address__c a : addrs) {
                String utxoJson = BlockfrostService.getAddressUtxos(a.Address__c);
                // Log full UTXO API response for transparency
                Logger.logDebug('UTXO API response for '+a.Address__c+': '+utxoJson);
                List<Object> listU = (List<Object>) JSON.deserializeUntyped(utxoJson);
                for (Object recObj : listU) {
                    Map<String,Object> rec = (Map<String,Object>) recObj;
                    List<Object> amounts = (List<Object>) rec.get('amount');
                    for (Object amtObj : amounts) {
                        Map<String,Object> amt = (Map<String,Object>) amtObj;
                        String unit = String.valueOf(amt.get('unit'));
                        Decimal qty = Decimal.valueOf(String.valueOf(amt.get('quantity')));
                        if (!unitAddrQty.containsKey(unit)) {
                            unitAddrQty.put(unit, new Map<Id, Decimal>());
                        }
                        Map<Id, Decimal> addrMap = unitAddrQty.get(unit);
                        addrMap.put(a.Id, (addrMap.containsKey(a.Id)?addrMap.get(a.Id):0) + qty);
                        units.add(unit);
                    }
                }
            }

            // Fetch metadata for non-lovelace units
            Map<String, Id> unitToAssetId = new Map<String, Id>();
            Map<String, String> unitToIcon = new Map<String, String>();
            for (String unitKey : units) {
                if (unitKey == 'lovelace') {
                    unitToAssetId.put(unitKey, [SELECT Id FROM Asset__c WHERE Name='ADA' LIMIT 1].Id);
                    // Native ADA doesn't have an icon, skip icon processing
                } else {
                    String metaJson = BlockfrostService.getAssetMetadata(unitKey);
                    // Log full asset metadata response
                    Logger.logDebug('Asset metadata for '+unitKey+': '+metaJson);
                    unitToAssetId.put(unitKey, getAssetId(unitKey, metaJson));
                    if (metaJson != null && metaJson != '{}' ) {
                        Map<String,Object> metaMap = (Map<String,Object>) JSON.deserializeUntyped(metaJson);
                        if (metaMap.containsKey('logo')) {
                            String iconStr = String.valueOf(metaMap.get('logo'));
                            unitToIcon.put(unitKey, iconStr);
                            Logger.logInfo('Extracted logo for '+unitKey+': '+iconStr);
                        } else if (metaMap.containsKey('onchain_metadata')) {
                            Map<String,Object> oc = (Map<String,Object>) metaMap.get('onchain_metadata');
                            if (oc.containsKey('image')) {
                                String iconStr = String.valueOf(oc.get('image'));
                                unitToIcon.put(unitKey, iconStr);
                                Logger.logInfo('Extracted onchain image for '+unitKey+': '+iconStr);
                            }
                        }
                    }
                }
            }

            // Existing UTXO_Assets
            Map<String, UTXO_Asset__c> existing = new Map<String, UTXO_Asset__c>();
            for (UTXO_Asset__c ua : [SELECT Id, UTXO_Address__c, Blockfrost_ID__c, Icon__c, Amount__c FROM UTXO_Asset__c WHERE UTXO_Address__c IN :addrs]) {
                existing.put(ua.Blockfrost_ID__c + ':' + ua.UTXO_Address__c, ua);
            }

            List<UTXO_Asset__c> inserts = new List<UTXO_Asset__c>();
            List<UTXO_Asset__c> updates = new List<UTXO_Asset__c>();
            List<UTXO_Asset__c> deletes = new List<UTXO_Asset__c>();

            for (String unitKey : unitAddrQty.keySet()) {
                Id assetId = unitToAssetId.get(unitKey);
                Map<Id, Decimal> addrMap = unitAddrQty.get(unitKey);
                for (Id addrId : addrMap.keySet()) {
                    Decimal qty = addrMap.get(addrId);
                    Decimal adaQty = (unitKey=='lovelace') ? qty/1000000 : qty; // tokens kept raw quantity
                    String composite = unitKey + ':' + addrId;
                    if (existing.containsKey(composite)) {
                        UTXO_Asset__c rec = existing.get(composite);
                        if (adaQty == 0) deletes.add(rec); else {
                            rec.Amount__c = adaQty;
                            if (String.isBlank(rec.Icon__c) && unitToIcon.containsKey(unitKey)) {
                                rec.Icon__c = unitToIcon.get(unitKey);
                                Logger.logInfo('Update icon for existing UTXO_Asset '+rec.Id+' unit '+unitKey);
                            }
                            updates.add(rec);
                        }
                    } else {
                        if (adaQty > 0) {
                            String iconVal = unitToIcon.containsKey(unitKey)?unitToIcon.get(unitKey):null;
                            inserts.add(new UTXO_Asset__c(UTXO_Address__c=addrId, Asset__c=assetId, Amount__c=adaQty, Blockfrost_ID__c=unitKey, Icon__c= iconVal));
                            if (iconVal!=null) Logger.logInfo('Insert UTXO_Asset with icon for '+unitKey+' addr '+addrId);
                        }
                    }
                }
            }

            List<UTXO_Asset__c> upserts2 = new List<UTXO_Asset__c>();
            upserts2.addAll(inserts);
            upserts2.addAll(updates);
            if (!upserts2.isEmpty()) upsert upserts2 Blockfrost_ID__c;
            if (!deletes.isEmpty()) delete deletes;

        } catch (Exception e) {
            throw new AuraHandledException('Failed to sync assets: '+e.getMessage());
        }
    }

    /**
     * Returns all UTXO_Asset__c records for a wallet, including ADA and tokens, with their UTXO address, Blockfrost unit, and amount.
     */
    @AuraEnabled(cacheable=true)
    public static List<UTXO_Asset__c> getAllUtxoAssetsForWallet(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            List<UTXO_Address__c> utxoAddresses = [SELECT Id FROM UTXO_Address__c WHERE Wallet__c = :walletId];
            if (utxoAddresses.isEmpty()) {
                return new List<UTXO_Asset__c>();
            }
            Set<Id> utxoAddressIds = new Set<Id>();
            for (UTXO_Address__c addr : utxoAddresses) utxoAddressIds.add(addr.Id);
            return [SELECT Id, UTXO_Address__c, Blockfrost_ID__c, Amount__c, Asset__c, Icon__c FROM UTXO_Asset__c WHERE UTXO_Address__c IN :utxoAddressIds];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching UTXO assets for wallet: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String createOutboundTransaction(String walletId, String recipientAddress, String amount, String fee, String changeAddress, String transactionData, String inputs, String outputs, String metadata, String protocolParams) {
        try {
            Outbound_Transaction__c outboundTx = new Outbound_Transaction__c();
            outboundTx.Transaction_Status__c = 'New';
            outboundTx.Approved__c = 'Not Approved';
            outboundTx.Recipient_Address__c = recipientAddress;
            outboundTx.Amount__c = amount != null ? Decimal.valueOf(amount) : null;
            outboundTx.Fee__c = fee != null ? Decimal.valueOf(fee) : null;
            outboundTx.Change_Address__c = changeAddress;
            outboundTx.Transaction_Data__c = transactionData;
            outboundTx.Inputs__c = inputs;
            outboundTx.Outputs__c = outputs;
            outboundTx.Metadata__c = metadata;
            outboundTx.Protocol_Parameters__c = protocolParams;
            insert outboundTx;
            return outboundTx.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to create outbound transaction: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateOutboundTransactionStatus(String transactionId, String status) {
        try {
            Outbound_Transaction__c tx = [SELECT Id, Transaction_Status__c FROM Outbound_Transaction__c WHERE Id = :transactionId LIMIT 1];
            tx.Transaction_Status__c = status;
            update tx;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update transaction status: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateOutboundTransactionDataAndStatus(String transactionId, String recipientAddress, String amount, String fee, String changeAddress, String transactionData, String inputs, String outputs, String metadata, String protocolParams) {
        try {
            Outbound_Transaction__c tx = [SELECT Id FROM Outbound_Transaction__c WHERE Id = :transactionId LIMIT 1];
            tx.Transaction_Data__c = transactionData;
            tx.Recipient_Address__c = recipientAddress;
            tx.Amount__c = amount != null ? Decimal.valueOf(amount) : null;
            tx.Fee__c = fee != null ? Decimal.valueOf(fee) : null;
            tx.Change_Address__c = changeAddress;
            tx.Inputs__c = inputs;
            tx.Outputs__c = outputs;
            tx.Metadata__c = metadata;
            tx.Protocol_Parameters__c = protocolParams;
            tx.Transaction_Status__c = 'Prepared';
            update tx;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update transaction data and status: ' + e.getMessage());
        }
    }
}