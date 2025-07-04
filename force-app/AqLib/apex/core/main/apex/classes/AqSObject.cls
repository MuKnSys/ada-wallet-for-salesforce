/*
 * Copyright (c) 2022, Aquiva Labs LLC. All rights reserved.
 * 
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 *   are permitted provided that the following conditions are met:
 * 
 * - Redistributions of source code must retain the above copyright notice, 
 *     this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, 
 *     this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * - Neither the name of the Aquiva Labs LLC nor the names of its contributors
 *     may be used to endorse or promote products derived from this software without
 *     specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/
/**
 * @description Helper methods for SObject
 * @group apex/core
 */
public inherited sharing class AqSObject {

    public static Map<String, Schema.SObjectType> objectsTokensMap {
        get {
            if (objectsTokensMap == null) {
                Map<String, Schema.SObjectType> allTokens = Schema.getGlobalDescribe();
                objectsTokensMap = new Map<String, Schema.SObjectType>();
                for (String objName : allTokens.keySet()) {
                    objectsTokensMap.put(objName.toLowerCase(), allTokens.get(objName));
                }
            }
            return objectsTokensMap;
        }
        private set{}
    }
    private static Map<String, Schema.DescribeSObjectResult> objectDescribesMap = new Map<String, Schema.DescribeSObjectResult>();
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Token methods

    //Convert string sobject type name to token
    public static sObjectType getToken(String objectName) {
        sObjectType result = objectsTokensMap.get(Aq.appendPrefix(objectName).toLowerCase());
        if (result == null) {
            result = objectsTokensMap.get(objectName.toLowerCase());
        }
        return result;
    }

    public static Schema.DescribeSObjectResult getObjectDescribe (String objectName) {

        String lowercaseObjName = Aq.appendPrefix(objectName.toLowerCase());

        if (objectDescribesMap.containsKey(lowercaseObjName)) {
            return objectDescribesMap.get(lowercaseObjName);
        }

        Schema.SObjectType objToken = getToken(objectName);
        if (objToken == null) {
            throw new Aq.NotFoundException('Object token not found for: ' + objectName);
        }

        Schema.DescribeSObjectResult objectDescribe = objToken.getDescribe();
        objectDescribesMap.put(lowercaseObjName, objectDescribe);

        return objectDescribe;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //CRUD convenience methods

    // based on object API name
    public static Boolean isAccessible (String objectName) {
        return getObjectDescribe(objectName).isAccessible();
    }

    public static Boolean isCreateable (String objectName) {
        return getObjectDescribe(objectName).isCreateable();
    }

    public static Boolean isUpdateable (String objectName) {
        return getObjectDescribe(objectName).isUpdateable();
    }

    public static Boolean isDeletable (String objectName) {
        return getObjectDescribe(objectName).isDeletable();
    }

    public static void requireAccessible (String objectName) {
        if (!isAccessible(objectName)) {
            throw new Aq.PermissionException(
                Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireAccessible: ' +objectName + ')')
            );
        }
    }

    public static void requireCreateable (String objectName) {
        if (!isCreateable(objectName)) {
            throw new Aq.PermissionException(
                Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireCreateable: ' + objectName + ')')
            );
        }
    }

    public static void requireUpdateable (String objectName) {
        if (!isUpdateable(objectName)) {
            throw new Aq.PermissionException(
                Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireUpdateable: ' + objectName + ')')
            );
        }
    }

    public static void requireDeletable (String objectName) {
        if (!isDeletable(objectName)) {
            throw new Aq.PermissionException(
                Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireDeletable: ' + objectName + ')')
            );
        }
    }


    // based on the SObjectType
    public static Boolean isAccessible(SObjectType objectType) {
        return objectType.getDescribe().isAccessible();
    }

    public static Boolean isCreateable(SObjectType objectType) {
        return objectType.getDescribe().isCreateable();
    }

    public static Boolean isUpdateable(SObjectType objectType) {
        return objectType.getDescribe().isUpdateable();
    }

    public static Boolean isDeletable(SObjectType objectType) {
        return objectType.getDescribe().isDeletable();
    }

    public static void requireAccessible(SObjectType objectType) {
        if (!isAccessible(objectType)) {
            throw new Aq.PermissionException(Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireAccessible: ' + String.valueOf(objectType) + ')'));
        }
    }

    public static void requireCreateable(SObjectType objectType) {
        if (!isCreateable(objectType)) {
            throw new Aq.PermissionException(Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireCreateable: ' + String.valueOf(objectType) + ')'));
        }
    }

    public static void requireUpdateable(SObjectType objectType) {
        if (!isUpdateable(objectType)) {
            throw new Aq.PermissionException(Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireUpdateable: ' + String.valueOf(objectType) + ')'));
        }
    }

    public static void requireDeletable(SObjectType objectType) {
        if (!isDeletable(objectType)) {
            throw new Aq.PermissionException(Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireDeletable: ' + String.valueOf(objectType) + ')'));
        }
    }

}
