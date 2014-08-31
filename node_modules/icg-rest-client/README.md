## ICG Rest client

A simple rest client that reduces the amount of call management code that is required to use a typical rest/json API

### Usage

    var ICGRestClient = require("icg-rest-client");

    // Create the client with the API base url
    client = ICGRestClient("http://api.com/api");

    client.get("resource", {}, function(err, data){

    })

    client.get("resource", {headers:secToken}, function(err, data){
      ...
    })

    client.post("resource", {headers:secToken, data:{name:"Test"}}, function(err, data){
      ...
    })

    client.put("resource/12", {headers:secToken, data:{name:"Test"}}, function(err, data){
      ...
    })
