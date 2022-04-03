#include <curl/curl.h>
#include <iostream>
#include <string>
#include "nlohmann/json.hpp"

using nlohmann::json;

struct memory {
    char *response;
    size_t size;
};

class Downloader
{
    private:
        CURL *curl;
        memory *chunk = new memory {0};

        static size_t callback(void *data, size_t size, size_t nmemb, void *userp) {
            size_t realsize = size * nmemb;
            memory *mem = (memory *)userp;
 
            auto ptr = (char *) realloc(mem->response, mem->size + realsize + 1);
            if (ptr == NULL)
                return 0;
 
            mem->response = ptr;
            memcpy(&(mem->response[mem->size]), data, realsize);
            mem->size += realsize;
            mem->response[mem->size] = 0;
 
            return realsize;
        }

    public:
        Downloader(std::string url) {
            //curl_global_init(CURL_GLOBAL_DEFAULT);
 
            curl = curl_easy_init();
            if (curl) {
                curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
                curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, callback);
                curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)chunk);
            }
        }
        ~Downloader() {
            if(curl) {
                curl_easy_cleanup(curl);
            }
            //curl_global_cleanup();
            std::cout << "Downloader successfully destroyed.\n" << std::endl;
        }

        json download() {
            auto res = curl_easy_perform(curl);
            if(res != CURLE_OK)
                fprintf(stderr, "curl_easy_perform() failed: %s\n", curl_easy_strerror(res));

            // parse data to json
        	auto data = json::parse(chunk->response);

            return data;
        }
};