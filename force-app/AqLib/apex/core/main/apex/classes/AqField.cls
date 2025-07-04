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
 * @description Methods for working with SObject fields.
 * @group apex/core
 */
public inherited sharing class AqField {

    public static final String RECORD_TYPE_ID = 'RecordTypeId';

    private static final String USERNAME_FIELD_NAME = 'username';
    private static Map<String, Map<String, Schema.SObjectField>> fieldTokensMap
        = new Map<String, Map<String, Schema.SObjectField>>();
    private static Map<String, Map<String, Schema.DescribeFieldResult>> fieldDescribesMap
        = new Map<String, Map<String, Schema.DescribeFieldResult>>();

    // get field describe based on object name and field name
    public static Schema.DescribeFieldResult getFieldDescribe(String objectTypeName, String fieldPath) {

        String lowerCaseFieldPath = fieldPath.toLowerCase();
        Map<String, Schema.DescribeFieldResult> fieldDescribeByName = fieldDescribesMap.get(objectTypeName);
        if (fieldDescribeByName == null) {
            fieldDescribeByName = new Map<String, Schema.DescribeFieldResult>();
            fieldDescribesMap.put(objectTypeName, fieldDescribeByName);
        } else if (fieldDescribeByName.containsKey(lowerCaseFieldPath)) {
            return fieldDescribeByName.get(lowerCaseFieldPath);
        }

        SObjectType objectType = AqSObject.getToken(objectTypeName);
        Schema.SObjectField field = getToken(objectType, lowerCaseFieldPath);
        Schema.DescribeFieldResult result = field.getDescribe();
        fieldDescribeByName.put(lowerCaseFieldPath, result);
        return result;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Token methods

    // Convert string field name to token. Supports dotted join notation for relationships.
    public static SObjectField getToken(SObjectType objectType, String fieldPath) {

        String lowerCaseFieldPath = fieldPath.toLowerCase();
        String objectAPIName = String.valueOf(objectType).toLowerCase();
        String[] segments = lowerCaseFieldPath.split('\\.');

        if (segments.size() > 1) {
            String relationshipFieldName = segments[0].endsWith('__r') ? segments[0].left(segments[0].length() - 1) + 'c' : segments[0] + 'Id';
                SObjectField relationshipField = getToken(objectType, relationshipFieldName);
            List<SObjectType> relatedObjectTypes = relationshipField.getDescribe().getReferenceTo();
            if (relatedObjectTypes == null || relatedObjectTypes.isEmpty()) {
                throw new Aq.NotFoundException('Field token not found for: ' + String.valueOf(objectType) + '.' + fieldPath);
            }
            String fieldPathContinuation = lowerCaseFieldPath.substring(segments[0].length() + 1);
            return getToken(relatedObjectTypes[0], fieldPathContinuation);
        }

        if (!fieldTokensMap.containsKey(objectAPIName)) {
            fieldTokensMap.put(objectAPIName, objectType.getDescribe().fields.getMap());
        }
        
        String namespacedName = Aq.appendPrefix(lowerCaseFieldPath);
        SObjectField result = fieldTokensMap.get(objectAPIName).get(namespacedName);
        if (result == null) {
            // in case we want to get org's custom field without prefix from managed package context
            // search unprefixed field name in the object fields map
            result = fieldTokensMap.get(objectAPIName).get(lowerCaseFieldPath);
            if (result == null) {
                throw new Aq.NotFoundException('Field token not found for: ' + String.valueOf(objectType) + '.' + fieldPath);
            }
        }
        return result;
    }

    public static String getFieldName(SObjectField sObjectField) {
        return sObjectField.getDescribe().getName();
    }

    public static String getRelationshipName(SObjectField sObjectField) {
        return sObjectField.getDescribe().getRelationshipName();
    }

    //Convert string field name to token
    public static SObjectField getToken(SObject record, String fieldName) {
        return getToken(record.getSObjectType(), fieldName);
    }

    public static Schema.SoapType getSOAPType(String objectTypeName, String fieldName) {
        return getSOAPType(getFieldDescribe(objectTypeName, fieldName));
    }

    public static Schema.SoapType getSOAPType(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe.getSoapType();
    }

    public static Schema.DisplayType getType(String objectTypeName, String fieldName) {
        return getType(getFieldDescribe(objectTypeName, fieldName));
    }

    public static Schema.DisplayType getType(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe.getType();
    }

    public static Boolean isEmailField(Schema.DescribeFieldResult fieldDescribe) {
        return getType(fieldDescribe) == Schema.DisplayType.EMAIL;
    }

    public static Boolean isUsernameField(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe.getName().toLowerCase() == USERNAME_FIELD_NAME;
    }

    public static Boolean isStringSOAPType(Schema.DescribeFieldResult fieldDescribe) {
        return getSOAPType(fieldDescribe) == Schema.SoapType.STRING;
    }

    public static Boolean isBooleanSOAPType(Schema.DescribeFieldResult fieldDescribe) {
        return getSOAPType(fieldDescribe) == Schema.SoapType.BOOLEAN;
    }

    public static Boolean isRequiredField(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe.isCreateable() && !fieldDescribe.isNillable() && !isBooleanSOAPType(fieldDescribe);
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //FLS convenience methods

    // isAccessible
    public static Boolean isAccessible(String objectName, String fieldName) {
        return getFieldDescribe(objectName, fieldName).isAccessible();
    }

    public static void requireAccessible(String objectName, String fieldName) {
        if (!isAccessible(objectName, fieldName)) {
            throw new Aq.PermissionException(Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireAccessible: ' + objectName + '.' + fieldName + ')'));
        }
    }

    public static void requireAccessible(String objectName, Set<String> fieldNames) {
        for (String fieldName : fieldNames) {
            requireAccessible(objectName, fieldName);
        }
    }

    // isCreateable
    public static Boolean isCreateable(String objectName, String fieldName) {
        Schema.DescribeFieldResult fieldDescribe = getFieldDescribe(objectName, fieldName);
        return fieldDescribe.isCreateable() || !fieldDescribe.isPermissionable();
    }

    public static void requireCreateable(String objectName, String fieldName) {

        if (!isCreateable(objectName, fieldName)) {
            throw new Aq.PermissionException(
                Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireCreateable: ' + objectName + '.' + fieldName + ')')
            );
        }
    }

    public static void requireCreateable(String objectName, Set<String> fieldNames) {
        for (String fieldName : fieldNames) {
            requireCreateable(objectName, fieldName);
        }
    }

    // isUpdateable
    public static Boolean isUpdateable(String objectName, String fieldName) {
        Schema.DescribeFieldResult fieldDescribe = getFieldDescribe(objectName, fieldName);
        return fieldDescribe.isUpdateable() || !fieldDescribe.isPermissionable();
    }

    public static void requireUpdateable(String objectName, String fieldName) {

        if (!isUpdateable(objectName, fieldName)) {
            throw new Aq.PermissionException(
                Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireUpdateable: ' + objectName + '.' + fieldName + ')')
            );
        }
    }

    public static void requireUpdateable(String objectName, Set<String> fieldNames) {
        for (String fieldName : fieldNames) {
            requireUpdateable(objectName, fieldName);
        }
    }


    // based on sObjectField
    public static Boolean isAccessible(SObjectField field) {
        return isAccessible(field.getDescribe());
    }

    public static Boolean isCreateable(SObjectField field) {
        return isCreateable(field.getDescribe());
    }

    public static Boolean isUpdateable(SObjectField field) {
        return isUpdateable(field.getDescribe());
    }

    // based on DescribeFieldResult
    public static Boolean isAccessible(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe.isAccessible();
    }

    public static Boolean isCreateable(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe.isCreateable() || !fieldDescribe.isPermissionable();
    }

    public static Boolean isUpdateable(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe.isUpdateable() || !fieldDescribe.isPermissionable();
    }

    public static void requireAccessible(SObjectField field) {
        if (!isAccessible(field)) {
            throw new Aq.PermissionException(Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireAccessible: ' + String.valueOf(field) + ')'));
        }
    }

    public static void requireCreateable(SObjectField field) {
        if (!isCreateable(field)) {
            throw new Aq.PermissionException(Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireCreateable: ' + String.valueOf(field) + ')'));
        }
    }

    public static void requireUpdateable(SObjectField field) {
        if (!isUpdateable(field)) {
            throw new Aq.PermissionException(Label.Aq_M_InsufficientPrivilege + AqEnv.ifDebugMode(' (requireUpdateable: ' + String.valueOf(field) + ')'));
        }
    }

    public static Boolean isPermissionableForDML(String objectName, String fieldName) {
        Schema.DescribeFieldResult fieldDescribe = getFieldDescribe(objectName, fieldName);
        return isPermissionableForDML(fieldDescribe);
    }

    public static Boolean isPermissionableForDML(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe.isPermissionable() && !fieldDescribe.isCalculated();
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Retrieve field values while checking Read and FLS for current user
    //These methods do NOT throw exceptions, they just return null if user doesn't have access

    //Retrieve the field value, or return null if user doesn't have permission to read the field
    public static Object get(SObject record, SObjectField field) {

        if (record == null) {
            return null;
        }

        AqSObject.requireAccessible(record.getSObjectType());

        if (isAccessible(field)) {

            try {
                return record.get(field);
            } catch (System.SObjectException e) {
                //Assume field wasn't queried in SOQL
                return null;
            }
        } else {
            return null;
        }
    }

    //Typed convenience methods to avoid have to cast return value

    public static String getString(SObject record, SObjectField field) {
        return (String) get(record, field);
    }

    public static Boolean getBoolean(SObject record, SObjectField field) {
        return (Boolean) get(record, field);
    }

    public static Date getDate(SObject record, SObjectField field) {
        return (Date) get(record, field);
    }

    public static Datetime getDatetime(SObject record, SObjectField field) {
        return (Datetime) get(record, field);
    }

    public static Integer getInteger(SObject record, SObjectField field) {
        return Integer.valueOf(get(record, field));
    }

    public static Decimal getDecimal(SObject record, SObjectField field) {
        return (Decimal) get(record, field);
    }

    //Get related object based on ID field
    public static SObject getSObject(SObject record, SObjectField field) {

        if (record == null) {
            return null;
        }

        AqSObject.requireAccessible(record.getSObjectType());

        if (isAccessible(field)) {

            try {
                return record.getSObject(field);
            } catch (System.SObjectException e) {
                //Assume field wasn't queried in SOQL
                return null;
            }
        } else {
            return null;
        }
    }

    //Return the UTC time stored in the datetime field in the user's local time
    //This purposely will return a datetime with an indicated timezone of GMT/UTC/Z but the actual content will be in the current user's timezone.
    //This is because Salesforce JSON serialization always returns datetime with a timezone but for use when you wish the client to use the datetime
    //as shown.
    public static Datetime getDatetimeLocal(SObject record, SObjectField field) {
        Datetime utcDatetime = (Datetime) get(record, field);
        if (utcDatetime == null) {
            return null;
        } else {
            return Datetime.newInstanceGmt(utcDatetime.year(), utcDatetime.month(), utcDatetime.day(), utcDatetime.hour(), utcDatetime.minute(), utcDatetime.second());
        }
    }

    //Returns multi-select picklist value as list of strings
    public static List<String> getMultiSelectPicklist(SObject record, SObjectField field) {
        String valuesString = (String) get(record, field);
        if (String.isEmpty(valuesString)) {
            return new List<String>();
        } else {
            return valuesString.split(';');
        }
    }

    //Get records from child relationship
    public static SObject[] getChildRecords(SObject record, String relationshipName, SObjectType childType, Boolean required) {

        //If null record or child object isn't accessible to user, return empty array
        if (record == null || !AqSObject.isAccessible(childType)) {
            return new SObject[0];
        }

        try {
            return record.getSObjects(relationshipName);
        } catch (System.SObjectException e) {

            //SObject row was retrieved via SOQL without requesting...
            //In this case, we assume it was on purpose -- there's no other way to query whether the data was requested
            if (required == true) {
                throw e;
            } else {
                return  new SObject[0];
            }
        }
    }

    public static Map<SObjectField, Map<String, String>> picklistLabelsCache = new Map<SObjectField, Map<String, String>>();
    //Get label of a picklist value
    public static String getPicklistLabel(SObjectField field, String value) {
        if (field == null || value == null) {
            return null;
        }

        // use cache for optimization
        if (picklistLabelsCache.containsKey(field) && picklistLabelsCache.get(field).containsKey(value)) {
            return picklistLabelsCache.get(field).get(value);
        }
        
        if (!picklistLabelsCache.containsKey(field)) {
            picklistLabelsCache.put(field, new Map<String, String>());
        }

        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.getValue() == value) {
                String label = entry.getLabel();
                picklistLabelsCache.get(field).put(value, label);
                return label;
            }
        }
        throw new Aq.NotFoundException(AqString.format('No picklist entry found for {0}', value));
    }

    //Get properly formatted literal for soql
    public static String getSoqlLiteral(SObjectField field, String value) {

        if (value == null) {
            return 'null';
        }

        Schema.SoapType fieldType = field.getDescribe().getSoapType();
        if (fieldType == Schema.SoapType.BOOLEAN) {
            return String.valueOf(Boolean.valueOf(value));	//Assures that it converts
        } else if (fieldType == Schema.SoapType.DOUBLE) {
            if (field.getDescribe().getScale() == 0) {
                return String.valueOf(Integer.valueOf(value));	//Assures that it converts
            } else {
                return String.valueOf(Double.valueOf(value));	//Assures that it converts
            }
        } else if (fieldType == Schema.SoapType.INTEGER) {
            return String.valueOf(Integer.valueOf(value));	//Assures that it converts
        } else if (fieldType == Schema.SoapType.DATE) {
            if (!String.isEmpty(value) && value.toLowerCase() == 'today()') {
                return AqEnv.now().formatGmt('yyyy-MM-dd');
            } else {
                return value;
            }
        } else if (fieldType == Schema.SoapType.DATETIME) {
            if (!String.isEmpty(value) && value.toLowerCase() == 'now()') {
                return AqEnv.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            } else {
                return value;
            }
        } else {
            return '\'' + value.replace('\'', '\\\'') + '\'';	//Enclose in single quotes and escape all single quotes
        }
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Set field values while checking Create or Edit and FLS for current user

    //Put value into record only if current user has required privilege
    public static void put(SObject record, SObjectField field, Object value) {

        if (record.Id == null) {
            AqSObject.requireCreateable(record.getSObjectType());
            if (isCreateable(field)) {
                record.put(field, value);
            }
        } else {
            AqSObject.requireUpdateable(record.getSObjectType());
            if (isUpdateable(field)) {
                record.put(field, value);
            }
        }

    }

    public static void putBoolean(SObject record, SObjectField field, Boolean value) {
        if (value != null) {
            put(record, field, value);
        }
    }

    public static void putMultiSelectPicklist(SObject record, SObjectField field, List<String> values) {
        if (values != null) {
            put(record, field, String.join(values, ';'));
        }
    }

    public static Object getSObjectFieldValue(SObject record, String fieldName) {
        
        if (record == null || fieldName == null) {
            return null;
        }

        if (fieldName.contains('.')) {
            String[] arr = fieldName.split('\\.');
            SObject parentObject = record.getSObject(arr[0]);
            arr.remove(0);
            return getSObjectFieldValue(parentObject, String.join(arr, '.'));
        }

        return record.get(fieldName);
    }

    //Return generic picklist data for a field
    public static List<AqPicklistEntry> getPicklistEntries(SObjectField field) {

        Aq.requireValue('field', field);

        if (field.getDescribe().getType() != Schema.DisplayType.PICKLIST
        && field.getDescribe().getType() != Schema.DisplayType.MULTIPICKLIST) {
            throw new AqException(AqString.format('Field {0} is not a picklist.', field));
        }

        List<Schema.PicklistEntry> entries = field.getDescribe().getPicklistValues();
        List<AqPicklistEntry> result = new List<AqPicklistEntry>();

        for (Schema.PicklistEntry entry : entries) {
            result.add(new AqPicklistEntry(entry.getLabel(), entry.getValue(), entry.isDefaultValue()));
        }

        return result;
    }

}
