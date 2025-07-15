public with sharing class UTXOAssetController {
    private static void populateAssetFields(UTXO_Asset__c asset, String unit, Decimal totalAmount, String assetName, String displayUnit, Map<String, Object> metadata) {
        asset.Amount__c = totalAmount;
        asset.Asset__c = (unit == 'lovelace' ? 'ADA' : displayUnit);
        asset.Name__c = (unit == 'lovelace' ? 'Cardano' : assetName);
        asset.Icon__c = null;
        
        if (unit == 'lovelace') {
            asset.Decimals__c = 6;
            asset.Icon__c = null;
        } else {
            // For non-lovelace assets, try to get decimals from metadata
            if (metadata != null) {
                // Set Policy ID
                if (metadata.containsKey('policy_id') && metadata.get('policy_id') != null) {
                    asset.Policy_ID__c = String.valueOf(metadata.get('policy_id'));
                }
                // Set Fingerprint
                if (metadata.containsKey('fingerprint') && metadata.get('fingerprint') != null) {
                    asset.Fingerprint__c = String.valueOf(metadata.get('fingerprint'));
                }
                // Set Decimals from metadata
                if (metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                    Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                    if (innerMeta.containsKey('decimals') && innerMeta.get('decimals') != null) {
                        Object decimalsObj = innerMeta.get('decimals');
                        if (decimalsObj instanceof Integer) {
                            asset.Decimals__c = (Integer) decimalsObj;
                        } else if (decimalsObj instanceof Decimal) {
                            asset.Decimals__c = ((Decimal) decimalsObj).intValue();
                        } else {
                            asset.Decimals__c = Integer.valueOf(String.valueOf(decimalsObj));
                        }
                    } else {
                        // If no decimals in metadata, default to 0
                        asset.Decimals__c = 0;
                    }
                } else {
                    // If no metadata at all, default to 0
                    asset.Decimals__c = 0;
                }
                
                // Set Icon__c from logo if present at top level or in inner metadata
                if (metadata.containsKey('logo') && metadata.get('logo') != null) {
                    asset.Icon__c = String.valueOf(metadata.get('logo'));
                } else if (metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                    Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                    if (innerMeta.containsKey('logo') && innerMeta.get('logo') != null) {
                        asset.Icon__c = String.valueOf(innerMeta.get('logo'));
                    }
                }
            } else {
                // If no metadata at all, set defaults
                asset.Decimals__c = 0;
            }
        }
        
        // Fallback to default icon if not set
        if (asset.Icon__c == null) {
            asset.Icon__c = 'utility:money';
        }
    }
    
    /**
     * Synchronizes both assets and transactions for a UTXO address
     * @param utxoAddressId The UTXO Address ID to sync
     * @return Map with combined results
     */
    @AuraEnabled
    public static Map<String, Object> syncAssetsAndTransactions(Id utxoAddressId) {
        try {
            return UTXOHelper.syncAssetsAndTransactions(utxoAddressId);
        } catch (Exception e) {
            throw new AuraHandledException('Error syncing assets and transactions: ' + e.getMessage());
        }
    }            

    /**
     * Sets Is_Used__c = true for a list of UTXO_Address__c records
     * @param utxoAddressIds List of UTXO Address record IDs
     */
    @AuraEnabled
    public static void setAddressesUsed(List<Id> utxoAddressIds) {
        try {
            UTXOHelper.setAddressesUsed(utxoAddressIds);
        } catch (Exception e) {
            throw new AuraHandledException('Error setting addresses as used: ' + e.getMessage());
        }
    }

    /**
     * Get asset summary for a wallet (all assets across all UTXO addresses)
     * @param walletId The wallet ID to get assets for
     * @return Map with asset summary data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getWalletAssetSummary(Id walletId) {
        try {
            if (walletId == null) {
                throw new AuraHandledException('Wallet ID cannot be null');
            }
            
            // Get all UTXO addresses for this wallet
            List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getAddressesByWalletId(walletId);
            
            if (utxoAddresses.isEmpty()) {
                return new Map<String, Object>{
                    'success' => true,
                    'adaBalance' => 0,
                    'tokens' => new List<Object>(),
                    'totalAssets' => 0,
                    'message' => 'No UTXO addresses found for this wallet'
                };
            }
            
            Set<Id> utxoAddressIds = new Set<Id>();
            for (UTXO_Address__c addr : utxoAddresses) {
                utxoAddressIds.add(addr.Id);
            }
            
            // Get all assets for these addresses, aggregated by Asset
            AggregateResult[] assetAggregates = UTXOAssetSelector.getAssetAggregatesByUtxoAddressIds(utxoAddressIds);

            // Build a set of all asset units
            Set<String> assetUnits = new Set<String>();
            for (AggregateResult ar : assetAggregates) {
                assetUnits.add(String.valueOf(ar.get('Asset__c')));
            }
            // Query one UTXO_Asset__c per asset to get Icon__c
            Map<String, String> assetToIcon = new Map<String, String>();
            List<UTXO_Asset__c> allAssetsWithIcons = UTXOAssetSelector.getAllAssetsByUtxoAddressIds(utxoAddressIds);
            for (UTXO_Asset__c asset : allAssetsWithIcons) {
                if (assetUnits.contains(asset.Asset__c) && asset.Icon__c != null && !assetToIcon.containsKey(asset.Asset__c)) {
                    assetToIcon.put(asset.Asset__c, asset.Icon__c);
                }
            }
            
            Decimal adaBalance = 0;
            List<Map<String, Object>> tokens = new List<Map<String, Object>>();
            
            for (AggregateResult ar : assetAggregates) {
                String unit = String.valueOf(ar.get('Asset__c'));
                Decimal totalAmount = (Decimal) ar.get('totalAmount');
                Decimal totalValue = (Decimal) ar.get('totalValue');
                String assetName = String.valueOf(ar.get('assetName'));
                Integer decimals = ar.get('decimals') != null ? Integer.valueOf(ar.get('decimals')) : 0;
                String policyId = String.valueOf(ar.get('policyId'));
                String fingerprint = String.valueOf(ar.get('fingerprint'));
                
                if (unit == 'ADA') {
                    // For ADA, use the Value__c field which converts lovelace to ADA
                    adaBalance = totalValue != null ? totalValue : 0;
                } else {
                    // For tokens, add to tokens list
                    // Use Amount__c if Value__c is 0 or null, otherwise use Value__c
                    Decimal displayAmount = (totalValue != null && totalValue > 0) ? totalValue : totalAmount;
                    
                    Map<String, Object> tokenInfo = new Map<String, Object>{
                        'unit' => unit,
                        'name' => assetName != null ? assetName : unit,
                        'symbol' => unit, // Use Asset__c field as the ticker/symbol
                        'amount' => displayAmount, // Use appropriate amount
                        'rawAmount' => totalAmount, // Keep raw amount for reference
                        'decimals' => decimals,
                        'policyId' => policyId != 'null' ? policyId : null,
                        'fingerprint' => fingerprint != 'null' ? fingerprint : null,
                        'icon' => assetToIcon.containsKey(unit) ? assetToIcon.get(unit) : 'utility:money'
                    };
                    tokens.add(tokenInfo);
                }
            }
            
            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'adaBalance' => adaBalance,
                'tokens' => tokens,
                'totalAssets' => assetAggregates.size(),
                'message' => 'Asset summary retrieved successfully'
            };
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get wallet asset summary: ' + e.getMessage());
        }
    }
    
    /**
     * Get all transactions for a wallet
     * @param walletId The wallet ID to get transactions for
     * @return Map with transaction data
     */
    @AuraEnabled
    public static Map<String, Object> fetchWalletTransactions(Id walletId) {
        try {
            if (walletId == null) {
                throw new AuraHandledException('Wallet ID cannot be null');
            }
            
            // Get Inbound Transactions
            List<Inbound_Transaction__c> inboundTxs = InboundTransactionSelector.getInboundTransactionsByWalletId(walletId);
            
            // Get Outbound Transactions with joined lines
            List<Outbound_Transaction__c> outboundTxs = OutboundTransactionSelector.getOutboundTransactionsByWalletId(walletId);
            
            // Map inbound transactions for LWC
            List<Map<String, Object>> inbound = new List<Map<String, Object>>();
            for (Inbound_Transaction__c tx : inboundTxs) {
                inbound.add(new Map<String, Object>{
                    'Id' => tx.Id,
                    'Name' => tx.Name,
                    'Transaction_Hash__c' => tx.Transaction_Hash__c,
                    'CreatedDate' => tx.CreatedDate,
                    'UTXO_Address__c' => tx.UTXO_Address__c,
                    'type' => 'inbound'
                });
            }
            
            // Map outbound transactions for LWC
            List<Map<String, Object>> outbound = new List<Map<String, Object>>();
            for (Outbound_Transaction__c tx : outboundTxs) {
                List<Map<String, Object>> lines = new List<Map<String, Object>>();
                if (tx.Outbound_Transaction_Lines__r != null) {
                    for (Outbound_Transaction_Line__c line : tx.Outbound_Transaction_Lines__r) {
                        lines.add(new Map<String, Object>{
                            'Id' => line.Id,
                            'Asset__c' => line.Asset__c,
                            'Amount__c' => line.Amount__c
                        });
                    }
                }
                outbound.add(new Map<String, Object>{
                    'Id' => tx.Id,
                    'Name' => tx.Name,
                    'Transaction_Hash__c' => tx.Transaction_Hash__c,
                    'Transaction_Status__c' => tx.Transaction_Status__c,
                    'Memo__c' => tx.Memo__c,
                    'CreatedDate' => tx.CreatedDate,
                    'type' => 'outbound',
                    'lines' => lines
                });
            }
            
            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'inbound' => inbound,
                'outbound' => outbound,
                'totalInbound' => inbound.size(),
                'totalOutbound' => outbound.size(),
                'message' => 'Transactions retrieved successfully'
            };
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get wallet transactions: ' + e.getMessage());
        }
    }
    
    /**
     * Get all UTXO assets for a wallet
     * @param walletId The wallet ID to get assets for
     * @return Map with asset data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAllUtxoAssetsForWallet(Id walletId) {
        try {
            if (walletId == null) {
                throw new AuraHandledException('Wallet ID cannot be null');
            }
            // Get all UTXO addresses for this wallet
            List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getAddressesByWalletId(walletId);
            if (utxoAddresses.isEmpty()) {
                return new Map<String, Object>{
                    'success' => true,
                    'assets' => new List<Object>(),
                    'message' => 'No UTXO addresses found for this wallet'
                };
            }
            Set<Id> utxoAddressIds = new Set<Id>();
            for (UTXO_Address__c addr : utxoAddresses) {
                utxoAddressIds.add(addr.Id);
            }
            // Get all assets for these addresses
            List<UTXO_Asset__c> assets = UTXOAssetSelector.getAllAssetsByUtxoAddressIds(utxoAddressIds);
            List<Map<String, Object>> assetList = new List<Map<String, Object>>();
            for (UTXO_Asset__c asset : assets) {
                assetList.add(new Map<String, Object>{
                    'id' => asset.Id,
                    'asset' => asset.Asset__c,
                    'amount' => asset.Amount__c,
                    'value' => asset.Value__c,
                    'name' => asset.Name__c,
                    'decimals' => asset.Decimals__c,
                    'policyId' => asset.Policy_ID__c,
                    'fingerprint' => asset.Fingerprint__c,
                    'icon' => asset.Icon__c,
                    'utxoAddressId' => asset.UTXO_Address__c
                });
            }
            return new Map<String, Object>{
                'success' => true,
                'assets' => assetList,
                'message' => 'Assets retrieved successfully'
            };
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get wallet assets: ' + e.getMessage());
        }
    }
} 