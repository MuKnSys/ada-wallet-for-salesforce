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
 * Builder class for SOSL quieries.
 *
 * @group apex/core
 */
public inherited sharing class AqSosl {

    /**
     *  Search scope (Name fields, Email fields, all fields etc.)
     */
    public enum Scope {
        ALL_FIELDS,
        NAME_FIELDS,
        EMAIL_FIELDS,
        PHONE_FIELDS,
        SIDEBAR_FIELDS
    }

    private final static String LIMIT_KEY = 'limit';
    private final static String FIELDS_KEY = 'fields';
    private final static String WHERE_KEY = 'where';
    private final static String ORDERBY_KEY = 'orderby';
    private final static String FIND_WILD_CARD = '*';

    private Scope currentScope = Scope.ALL_FIELDS;
    private Map<String, Map<String, String>> objectSearchConfig;
    private Map<String, List<SObject>> resultMap;
    private Boolean userMode = true;

    /**
     * Use it to omit `WITH USER_MODE`. Turned on by default.
     */
    public AqSosl withoutUserMode() {
        userMode = false;
        return this;
    }

    /**
     * @param scope set of fields searched by the sosl query. See [Scope](#scope)
     */
    public AqSosl setSearchScope(Scope scope) {
        this.currentScope = scope;
        return this;
    }

    /**
     *  Sets the objects that will be queried.
     *  @param  searchObjects  a list of SObject Type names.
     *
     */
    public AqSosl setSearchObjects(List<String> searchObjects) {

        Aq.requireNonemptyList('searchObjects', searchObjects);
        this.objectSearchConfig = new Map<String, Map<String, String>>();

        for (String searchObject : searchObjects) {
            AqSObject.requireAccessible(searchObject);
            Map<String, String> options = new Map<String, String>();
            options.put(FIELDS_KEY, 'Id');
            options.put(WHERE_KEY, AqString.EMPTY);
            options.put(LIMIT_KEY, AqString.EMPTY);
            options.put(ORDERBY_KEY, AqString.EMPTY);

            this.objectSearchConfig.put(searchObject, options);
        }
        return this;
    }

    /**
     *  Sets the fields that will be returned in the search query for the given object.
     *
     *  @param  objectName  an SObject Type name
     *  @param  fields      a list of field names
     *
     */
    public AqSosl setFieldsForObject(String objectName, List<String> fields) {

        Aq.requireValue('objectName', objectName);
        AqSObject.requireAccessible(objectName);

        Aq.requireValue('fields', fields);

        for (String fieldName : fields) {
            AqField.requireAccessible(objectName, fieldName);
        }
        Map<String, String> options = this.objectSearchConfig.get(objectName);
        options.put(FIELDS_KEY, String.join(fields, AqString.COMMA));
        this.objectSearchConfig.put(objectName, options);
        return this;
    }

    /**
     *  Sets the number of records to limit the search results for the given object.
     *
     *  @param  objectName  an SObject Type name
     *  @param  lmt         an integer
     *
     */
    public AqSosl setLimitForObject(String objectName, Integer lmt) {
        if (lmt >= 0) {
            Map<String, String> options = this.objectSearchConfig.get(objectName);
            options.put(LIMIT_KEY, 'LIMIT ' + String.valueOf(lmt));
            this.objectSearchConfig.put(objectName, options);
        }
        return this;
    }

    /**
     *  Sets the WHERE clause of a sosl search for the given object.
     *
     *  @param  objectName  an SObject Type name
     *  @param  condition   filters for a Where clause
     *
     */
    public AqSosl setConditionForObject(String objectName, String condition) {
        if (String.isNotBlank(condition)) {
            Map<String, String> options = this.objectSearchConfig.get(objectName);
            options.put(WHERE_KEY, 'WHERE ' + condition);
            this.objectSearchConfig.put(objectName, options);
        }
        return this;
    }

    /**
     *  Sets the OREDER BY parameter of a sosl search for the given object.
     *
     *  @param  objectName      an SObject Type name
     *  @param  orderByItems    list of fields to order by
     *
     */
    public AqSosl setOrderByForObject(String objectName, List<String> orderByItems) {

        Aq.requireValue('objectName', objectName);

        if (orderByItems != null && !orderByItems.isEmpty()) {
            Map<String, String> options = this.objectSearchConfig.get(objectName);
            options.put(ORDERBY_KEY, AqString.format(
                ' ORDER BY {0} ',
                String.join(orderByItems, AqString.COMMA)
            ));
            this.objectSearchConfig.put(objectName, options);
        }
        return this;
    }

    /**
     *  @return  a Set that contains the SObject types that will be queried.
     *
     */
    public Set<String> getSearchObjects() {
        return this.objectSearchConfig.keySet();
    }

    /**
     *  This method executes the SOSL search and updates the internal state
     *  with the results ( or error ).
     *
     *  @param   searchText  the word or phrase to be searched.
     *  @example
     *  List<String> FIELDS_FOR_SELECTION = {'Name'};
     *  Integer SEARCH_RESULTS_LIMIT = 1000;
     *  public static List<Account> searchAccounts(String searchText) {
     *      String objectName = 'Account';
     *      String condition = 'Name != NULL';
     *      List<String> orderFields = {'Name'};
     *
     *      AqSosl sosl = new AqSosl()
     *          .setSearchObjects(new List<String>{ objectName })
     *          .setFieldsForObject(objectName, FIELDS_FOR_SELECTION)
     *          .setLimitForObject(objectName, SEARCH_RESULTS_LIMIT)
     *          .setConditionForObject(objectName, condition)
     *          .setOrderByForObject(objectName, orderFields)
     *          .find(searchText);
     *
     *      return sosl.getResultsForObject(objectName);
     *  }
     */
    public AqSosl find(String searchText) {

        List<List<SObject>> results = Search.query(this.getSoslQuery(searchText));
        this.resultMap = new Map<String, List<SObject>>();
        for (List<SObject> recordsOfOneType : results) {
            if (recordsOfOneType.size() > 0) {
                this.resultMap.put(recordsOfOneType.get(0).getSObjectType().getDescribe().getName(), recordsOfOneType);
            }
        }
        return this;
    }

    /**
     *  @param   objectName  an SObject Type name
     *  @return  a list of SObjects that were returned in the search.
     *
     */
    public List<SObject> getResultsForObject(String objectName) {
        return resultMap.get(objectName);
    }

    /**
     *  @param   objectName     an SObject Type name
     *  @param   soslResults    Sosl search results
     *  @return  a list of SObjects that were returned in the search for a given SObject
     *
     */
    public static List<SObject> getResultsForObject(String objectName, List<List<SObject>> soslResults) {
        for (List<SObject> objList : soslResults) {
            if (objList.size() > 0) {
                if (objList.get(0).getSObjectType().getDescribe().getName().equalsIgnoreCase(objectName)) {
                    return objList;
                }
            }
        }
        return null;
    }

    /**
     *  @return  a list of all SObject lists that were returned in the query.
     *
    **/
    public Map<String, List<SObject>> getResults() {
        return this.resultMap;
    }

    /**
     *  @return  a string representation of the search scope.
     *
     */
    private String getSearchScope() {
        return this.currentScope.name().replace('_', ' ');
    }

    /**
     *  @return  a String used in the sosl query to list the objects and their
     *           options.
     *
     */
    @TestVisible
    private String getSearchObjectsAsString() {

        String objectString = '';
        for (String s : this.objectSearchConfig.keySet()) {
            Map<String, String> options = this.objectSearchConfig.get(s);
            objectString += AqString.format(
                ',{0} ({1} {2} {3} {4})',
                s,
                options.get(FIELDS_KEY),
                options.get(WHERE_KEY),
                options.get(ORDERBY_KEY),
                options.get(LIMIT_KEY)
            );
        }
        return objectString.substring(1);
    }

    /**
     *  @return  a string representation of the user mode database operation.
     *
     */
    private String getSearchWithUserMode() {
        return usermode ? 'WITH USER_MODE' : '';
    }

    /**
     *  @return  a SOSL query string
     *
     */
    public String getSoslQuery(String searchText) {

        String searchTerm = this.splitSearchTextBySpaceAndGetCombinedByAnd(searchText);
        if (String.isBlank(searchTerm)) {
            throw new System.QueryException('SOSL failed to search empty string');
        }
        searchTerm = '\'' + String.escapeSingleQuotes(searchTerm) + '\'';
        String sosl = String.format(
            'FIND {0} IN {1} RETURNING {2} {3}',
            new List<String> {searchTerm, getSearchScope(), getSearchObjectsAsString(), getSearchWithUserMode()}
        );
        return sosl;
    }

    private String splitSearchTextBySpaceAndGetCombinedByAnd(String searchText) {

        String searchClause = AqString.EMPTY;
        if (String.isBlank(searchText)) {
            return searchClause;
        }

        List<String> searchWords = searchText.split(AqString.SPACE);
        List<String> searchWordsWildCarded = new List<String>();
        for (String searchWord : searchWords) {
            if (String.isBlank(searchWord)) {
                continue;
            }
            searchWordsWildCarded.add(searchWord + FIND_WILD_CARD);
        }
        searchClause = String.join(searchWordsWildCarded,
            AqString.SPACE + Aq.LOGICAL_SYMBOL_MAP.get(Aq.Logical.OP_AND) + AqString.SPACE);
        return searchClause.trim();
    }
}
