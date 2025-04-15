public with sharing class BlockfrostEndpoint {
    public static final String mainnetEndpointUrl = 'https://cardano-mainnet.blockfrost.io/api';
    public static final String apiVersion = 'v0';
    public static final String endpointFix = 'w3s';

    public HttpRequest request;
    public HTTPResponse response;

    public BlockfrostEndpoint() {
        request = new HttpRequest();
    }

    public BlockfrostEndpoint get() {
        request.setMethod('GET');
        return this;
    }    

    public BlockfrostEndpoint setEndpoint(String value) {
        request.setEndpoint(String.join(new List<String>{ mainnetEndpointUrl, apiVersion }, '/') + value);
        return this;
    }

    public BlockfrostEndpoint setHeaders(Map<String, String> nameToValue) {
        for (String name : nameToValue.keySet()) {
            request.setHeader(name, nameToValue.get(name));
        }
        return this;
    }    

    public BlockfrostEndpoint send() {
        Http http = new Http();
        response = http.send(request);
        return this;
    }

    public HTTPResponse getResponse() {
        return response;
    }

    public Integer getStatusCode() {
        return response.getStatusCode();
    }

    public class BlockfrostAPIException extends Exception {
    }
}
