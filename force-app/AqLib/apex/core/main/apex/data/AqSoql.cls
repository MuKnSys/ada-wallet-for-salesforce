/**
 * Copyright (c) 2023, Aquiva Labs LLC. All rights reserved.
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
 * @description Builder class for SOQL quieries
 *
 * @group apex/core
 */
public inherited sharing class AqSoql {

    private static final String SECURITY_ENFORCED = 'WITH SECURITY_ENFORCED';
    private static final String USER_MODE = 'WITH USER_MODE';

    private String sObjectTypeName;
    private Set<String> columns = new Set<String>();
    private String whereClause;
    private List<AqSoql> subSelects;
    private Integer rowLimit;
    private List<String> orderBy;
    private boolean isAggregated = false;
    private List<String> aggregatedColumns = new List<String>();
    private List<String> groupBy;
    private SecurityMode securityLevel = SecurityMode.SECURITY_ENFORCED;

    @TestVisible
    private enum SecurityMode {
        SECURITY_ENFORCED,
        USER_MODE,
        NONE
    }

    private static final Map<SecurityMode, String> securityModeToQueryClause = new Map<SecurityMode, String> {
        SecurityMode.SECURITY_ENFORCED => SECURITY_ENFORCED,
        SecurityMode.USER_MODE => USER_MODE
    };

    public AqSoql(SObjectType objType) {
        this.sObjectTypeName = objType.getDescribe().getName();
    }

    public AqSoql(String objTypeName) {
        this.sObjectTypeName = objTypeName;
    }

    /**
     *  Constructor for sub-select queries
     *
     *  @param  lookupField a lookup SObjectField
     *  @param  childObjectType SObjectType for a child
     *  @example
     *  List<String> FIELDS_FOR_SELECTION = {'Name'};
     *  Integer SEARCH_RESULTS_LIMIT = 1000;
     *  public static List<Account> searchAccounts(String name) {
     *      String condition = 'Name = :name';
     *      List<String> orderFields = { 'Name' };
     *      AqSoql aqSoql = new AqSoql(Account.getSObjectType())
     *          .withColumns(FIELDS_FOR_SELECTION)
     *          .withWhere(condition)
     *          .withOrderBy(orderFields)
     *          .withRowLimit(SEARCH_RESULTS_LIMIT);
     *      return Database.query(aqSoql.getQueryString());
     *  }
     */
    public AqSoql(SObjectField lookupField, SObjectType childObjectType) {
        Aq.requireValue('lookupField', lookupField);
        String fieldName = lookupField.getDescribe().getName();
        List<SObjectType> sobjects = lookupField.getDescribe().getReferenceTo();
        String myObjectTypeName;
        if (!Aq.isEmptyList(sobjects)) {
            SObjectType obj = sobjects[0];
            List<ChildRelationship> relations = obj.getDescribe().getChildRelationships();
            for (ChildRelationship cr : relations) {
                if (cr.getChildSObject() == childObjectType && cr.getField().getDescribe().getName() == fieldName) {
                    myObjectTypeName = cr.getRelationshipName();
                    break;
                }
            }
        }
        if (myObjectTypeName == null) {
            throw new AqException('Failed to find Relationship for the field ' + fieldName);
        }
        this.sObjectTypeName = myObjectTypeName;
    }

    public AqSoql(AqSoql soql) {
        this.sObjectTypeName = soql.sObjectTypeName;
        this.columns = soql.columns;
        this.whereClause = soql.whereClause;
        this.subSelects = soql.subSelects;
        this.rowLimit = soql.rowLimit;
        this.orderBy = soql.orderBy;
        this.securityLevel = soql.securityLevel;
    }

    /**
     * Set columns list you want to select
     *
     * @example
     * List<String> columnsToSelect = {'Name', 'Address__c'};
     * AqSoql soql = new AqSoql(obj)
     *      .withColumns(columnsToSelect);
     * List<Object> result = Database.query(soql.getQueryString());
     */
    public AqSoql withColumns(List<String> cols) {
        this.columns.addAll(cols);
        return this;
    }

    /**
     * Use to construct query with aggregations
     *
     * @example
     * AqAggregation ag = AqAggregation.max(AqTestObject__c.Date__c, 'alias');
     * // queries the Maximum value of 'Date__c' field of 'AqTestObject__c' object
     * AqSoql soql = new AqSoql(obj)
     *      .withAggregation(new List<AqAggregation> { ag });
     * List<AggregateResult> results = soql.aggregate();
     */
    public AqSoql withAggregation(List<AqAggregation> aggregations) {
        Aq.requireNonemptyList('aggregations', aggregations);
        for (AqAggregation ag : aggregations) {
            this.aggregatedColumns.add(ag.toString());
        }
        this.columns.addAll(this.aggregatedColumns);
        this.isAggregated = true;
        return this;
    }

    /**
     * Set GROUP BY columns for Aggregation querries only.
     *
     * @example
     * List<String> columnsToSelect = {'Name', 'Address__c'};
     * List<String> groubBy = {'Name'};
     * AqAggregation ag = AqAggregation.max(AqTestObject__c.Date__c, 'alias');
     * AqSoql soql = new AqSoql(obj)
     *      .withColumns(columnsToSelect)
     *      .withAggregation(new List<AqAggregation> { ag })
     *      .withGroupBy(groubBy); // groups results by 'Name' field
     * List<AggregateResult> results = soql.aggregate();
     */
    public AqSoql withGroupBy(List<String> gb) {
        this.groupBy = gb;
        this.columns.addAll(gb);
        return this;
    }

    /**
     * Set WHERE condition to query
     *
     * @example
     * List<String> columnsToSelect = {'Name', 'Address__c'};
     * // returns records Where Name is not Bull
     * AqSoql soql = new AqSoql(obj)
     *      .withWhere('Name != NULL')
     *      .withColumns(columnsToSelect);
     * List<Object> result = Database.query(soql.getQueryString());
     */
    public AqSoql withWhere(String wc) {
        this.whereClause = wc;
        return this;
    }

    /**
     * Add sub query to your query
     *
     * @example
     * AqSoql subQuery = new AqSoql('Relation__r')
     *      .withColumns('Price');
     * List<String> columnsToSelect = {'Name', 'Address__c'};
     * AqSoql soql = new AqSoql(obj)
     *      .withColumns(columnsToSelect)
     *      // queries each object record with 'Relation__c' related records list
     *      .withSubSelects(new List<AqSoql>{subQuery});
     * List<Object> result = Database.query(soql.getQueryString());
     */
    public AqSoql withSubSelects(List<AqSoql> ss) {
        this.subSelects = ss;
        return this;
    }

    /**
     * Set query records LIMIT
     *
     * @example
     * List<String> columnsToSelect = {'Name', 'Address__c'};
     * AqSoql soql = new AqSoql(obj)
     *      .withColumns(columnsToSelect)
     *      // selects only first 1000 records
     *      .withRowLimit(1000);
     * List<Object> result = Database.query(soql.getQueryString());
     */
    public AqSoql withRowLimit(Integer rl) {
        this.rowLimit = rl;
        return this;
    }

    /**
     * Set ORDER BY parameter to query
     *
     * @example
     * List<String> columnsToSelect = {'Name', 'Address__c'};
     * AqSoql soql = new AqSoql(obj)
     *      // displays records odered by 'Name' field and Descending
     *      .withOrderBy(new List<String>{ 'Name DESC' })
     *      .withColumns(columnsToSelect);
     * List<Object> result = Database.query(soql.getQueryString());
     */
    public AqSoql withOrderBy(List<String> ob) {
        this.orderBy = ob;
        return this;
    }

    /**
     * Use it to omit `WITH SECURITY_ENFORCED` and `WITH USER_MODE` settings.
     * Default value is `WITH SECURITY_ENFORCED`
     *
     * @example
     * List<String> columnsToSelect = {'Name', 'Address__c'};
     * AqSoql soql = new AqSoql(obj)
     *      // displays records odered by 'Name' field and Descending
     *      .withOrderBy(new List<String>{ 'Name DESC' })
     *      .withColumns(columnsToSelect)
     *      .withoutSecurityEnforced();
     * List<Object> result = Database.query(soql.getQueryString());
     */
    public AqSoql withoutSecurityEnforced() {
        this.securityLevel = SecurityMode.NONE;
        return this;
    }

    /**
     * Use it to set security level to `WITH SECURITY_ENFORCED`. Turned on by default.
     *
     * @example
     * List<String> columnsToSelect = {'Name', 'Address__c'};
     * AqSoql soql = new AqSoql(obj)
     *      // displays records odered by 'Name' field and Descending
     *      .withOrderBy(new List<String>{ 'Name DESC' })
     *      .withColumns(columnsToSelect)
     *      .withSecurityEnforced();
     * List<Object> result = Database.query(soql.getQueryString());
     */
    public AqSoql withSecurityEnforced() {
        this.securityLevel = SecurityMode.SECURITY_ENFORCED;
        return this;
    }

    /**
     * Use it to set security level to `WITH USER_MODE` which enforces sharing regardless of class declaration.
     *
     * @example
     * List<String> columnsToSelect = {'Name', 'Address__c'};
     * AqSoql soql = new AqSoql(obj)
     *     .withColumns(columnsToSelect)
     *     .withUserMode();
     * try {
     *     List<Object> result = Database.query(soql.getQueryString());
     * } catch (QueryException ex) {
     *     throw new Aq.QueryPermissionException(ex);
     * }
     */
    public AqSoql withUserMode() {
        this.securityLevel = SecurityMode.USER_MODE;
        return this;
    }

    /**
     * Use it as a final builder method to return assembled SOQL query
     *
     * @example
     * AqSoql soql = new AqSoql(obj)
     *      .withColumns(new List<String>{ 'Name' });
     * String soqlQuery = soql.getQueryString();
     * List<sObjects> records = Database.query(soqlQuery);
     */
    public String getQueryString() {

        List<String> columnsList = new List<String>(this.columns);
        Aq.requireNonEmptyList('columns', columnsList);
        Aq.requireValue('objectType', this.sObjectTypeName);

        String soql = 'SELECT ' + String.join(columnsList, ',');

        // Any subselects
        if (this.subSelects != null) {
            for (AqSoql subSelect : this.subSelects) {
                AqSoql subSelectClone = new AqSoql(subSelect);
                subSelectClone.withoutSecurityEnforced();
                soql += ', (' + subSelectClone.getQueryString() + ')';
            }
        }

        soql += ' FROM ' + this.sObjectTypeName;

        if (!String.isBlank(this.whereClause)) {
            soql += AqString.format(' WHERE {0} ', this.whereClause);
        }

        if (!SecurityMode.NONE.equals(this.securityLevel) && securityModeToQueryClause.containsKey(this.securityLevel)) {
            soql += AqString.format(' {0} ', securityModeToQueryClause.get(this.securityLevel));
        }

        if (!Aq.isEmptyList(this.orderBy)) {
            soql += AqString.format(' ORDER BY {0} ', String.join(this.orderBy, ','));
        }

        if (this.isAggregated && !Aq.isEmptyList(this.groupBy)) {
            soql += AqString.format(' GROUP BY {0} ', String.join(this.groupBy, ','));
        }

        if (this.rowLimit >= 0) {
            soql += AqString.format(' LIMIT {0} ', rowLimit);
        }

        return soql;
    }

    /**
     * Use it as a final method for aggregation querries
     *
     * @example
     * AqAggregation ag = AqAggregation.max(AqTestObject__c.Date__c, 'alias');
     * AqSoql soql = new AqSoql(obj)
     *      .withAggregation(new List<AqAggregation> { ag });
     * List<AggregateResult> results = soql.aggregate();
     */
    public List<AggregateResult> aggregate() {
        if (!this.isAggregated) {
            throw new AqException('You can not use AqSoql.aggregate() without aggregation operator');
        }

        return Database.query(getQueryString());
    }

    /**
     * Use it as a final method for COUNT querries
     *
     * @example
     * AqSoql soql = new AqSoql(obj)
     *      .withWhere('RequiredText__c != NULL);
     * // counts all records instead of quering it
     * Integer numberOfRecords = soql.countQuery();
     */
    public Integer countQuery() {
        String query = new AqSoql(this)
            .withColumns(new List<String>{ 'COUNT()' })
            .getQueryString();

        return Database.countQuery(query);
    }

    /**
     * Assemble SOQL string for a given SObjectType and columns set
     *
     * @example
     * Set<String> columnsToSelect = {'Name', 'Address__c'};
     * String soqlQuery = AqSoql.getBaseSoql(obj, columnsToSelect);
     * List<sObjects> records = Database.query(soqlQuery);
     */
    public static String getBaseSoql(SObjectType objectType, Set<String> columns) {
		return getBaseSoql(objectType, new List<String>(columns), null);
    }

    /**
     * Assemble SOQL string for a given SObjectType, columns set and sub queries list
     *
     * @example
     * AqSoql subQuery = new AqSoql('Relation__r')
     *      .withColumns('Price');
     * List<AqSoql> subQueries = new List<AqSoql>{ subQuery };
     * Set<String> columnsToSelect = {'Name', 'Address__c'};
     *
     * String soqlQuery = AqSoql.getBaseSoql(obj, columnsToSelect, subQueries)
     */
    public static String getBaseSoql(SObjectType objectType, List<String> columns, List<AqSoql> subSelects) {

        return new AqSoql(objectType)
            .withColumns(columns)
            .withSubSelects(subSelects)
            .getQueryString();
    }

}
