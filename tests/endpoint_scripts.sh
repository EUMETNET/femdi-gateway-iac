# SCRIPTS FOR TESTING API ENDPOINTS
# ----------------------------------------------------------------


# Testing function for API endpoints
test_endpoint() {
    local url=$1
    local expected_status=$2
    local description=$3
    local extra_args=$4
    

    echo -e "Testing: $description"
    echo "URL: $url"

    if [ -n "$extra_args" ]; then
        response=$(curl -s -o /dev/null -w "%{http_code}" $extra_args "$url")
    else
        response=$(curl -s -o /dev/null -w "%{http_code}" -I "$url")
    fi

    if [ "$response" -eq "$expected_status" ]; then
        echo "$url is healthy ($response OK)"
    else
        echo "$url returned status code $response, expected $expected_status"
    fi
}


#TESTING APISIX

test_apisix() {
    # Test APISIX health endpoint on both ports

    test_endpoint http://127.0.0.1:9080/apisix/health 200 "Apisix on port 9080"
    test_endpoint http://127.0.0.1:9181/apisix/health 200 "Apisix on port 9181"

    # Response should be something like {"message": "Hello from dummy upstream server web1"}
    #test_endpoint http://127.0.0.1:9080/apisix/health "Hello from dummy upstream server web1" "Apisix on port 9080 with API key" "-X GET 'apikey: your-api-key'"
    #test_endpoint http://127.0.0.1:9181/apisix/health "Hello from dummy upstream server web2" "Apisix on port 9181 with API key" "-X GET 'apikey: your-api-key'"

}


#TESTING VAULT 

# Two vaults instances should be running
# Perform health check on localhost:8200 and localhost:8203 

test_vault() {
    #test_endpoint http://localhost:8200/v1/sys/health 200 "Vault on port 8200" "-H 'X-Vault-Token: your_vault_token_here'"
    test_endpoint http://localhost:8200/v1/sys/health 200 "Vault on port 8200" "-H 'X-Vault-Token: 00000000-0000-0000-0000-000000000000'"
    test_endpoint http://localhost:8203/v1/sys/health 200 "Vault on port 8203" "-H 'X-Vault-Token: 00000000-0000-0000-0000-000000000000'"
}
   

#TESTING KEYCLOAK

test_keycloak() {
    # Test Keycloak health endpoint
    test_endpoint http://localhost:8080/ 200 "Keycloak on port 8080" "-d 'username=admin&password=admin'"
}


#TESTING DEV PORTAL

test_dev_portal() {
    # Test Dev Portal backend and frontend health endpoints
    test_endpoint http://localhost:8082/health 200 "Dev Portal Backend on port 8082"
    test_endpoint http://localhost:3002 200 "Dev Portal Frontend on port 3002" "-d 'username=user&password=user'"
}


#TESTING GEOWEB

test_geoweb() {
    # Test Geoweb Location endpoint
    test_endpoint http://0.0.0.0:8080/locations/healthcheck 200 "Geoweb Location on port 8080"
    # Test Geoweb Presets endpoints
    test_endpoint http://127.0.0.1:8080/viewpreset/healthcheck 200 "Geoweb View Preset on port 8080"
    test_endpoint http://127.0.0.1:8080/workspacepreset/healthcheck 200 "Geoweb Workspace Preset on port 8080"
        # Returns status code 200 with {'status': 'OK', 'service': 'Presets'} JSON. /healthcheck
        # Returns status code 200 with {'status': 'OK', 'service': 'NGINX'} JSON. /health_check 
}


#EUMETSAT

test_eumetsat() {
    # Test EUMETSAT VAULT
    test_endpoint https://vault.eumetsat.meteogate.eu 200 "EUMETSAT Vault"
    # Test EUMETSAT APISIX
    test_endpoint https://api.eumetsat.meteogate.eu 200 "EUMETSAT APISIX"
    # Test EUMETSAT APISIX alternative domain
    test_endpoint https://api.meteogate.eu 200 "EUMETSAT APISIX alternative domain"
    # Test EUMETSAT Keycloak
    test_endpoint https://keycloak.meteogate.eu 200 "EUMETSAT Keycloak"
    # Test EUMETSAT Geoweb
    test_endpoint https://explorer.meteogate.eu 200 "EUMETSAT Geoweb"
    # Test EUMETSAT Dev Portal Frontend
    test_endpoint https://devportal.meteogate.eu 200 "EUMETSAT Dev Portal Frontend"
    # Test EUMETSAT Dev Portal Backend (not accessible yet from outside)
    #test_endpoint https://insert_address 200 "EUMETSAT Dev Portal Backend"
}


#ECMWF

test_ecmwf() {
    # Test ECMWF VAULT
    test_endpoint https://vault.ecmwf.meteogate.eu 200 "ECMWF Vault"
    # Test EMCWF APISIX
    test_endpoint https://api.ecmwf.meteogate.eu 200 "ECMWF APISIX"
}

# ----------------------------------------------------------------

# Main execution
main() {
    echo "======================================================"
    echo "                 Endpoint Testing"
    echo "======================================================"
    
    # Run tests
    test_apisix
    test_vault
    test_keycloak
    test_dev_portal
    test_geoweb
    test_eumetsat
    test_ecmwf

    echo -e "\n======================================================"
    print_status "INFO" "Endpoint testing completed"
    echo "======================================================"
}

# Run the script
main "$@"