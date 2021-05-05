# HW: Search Engine

In this assignment you will create a highly scalable web search engine.

**Due Date:** Sunday, 9 May

**Learning Objectives:**
1. Learn to work with a moderate large software project
1. Learn to parallelize data analysis work off the database
1. Learn to work with WARC files and the multi-petabyte common crawl dataset
1. Increase familiarity with indexes and rollup tables for speeding up queries

## Task 0: project setup

1. Fork this github repo, and clone your fork onto the lambda server

1. Ensure that you'll have enough free disk space by:
    1. bring down any running docker containers
    1. run the command
       ```
       $ docker system prune
       ```

## Task 1: getting the system running

In this first task, you will bring up all the docker containers and verify that everything works.

There are three docker-compose files in this repo:
1. `docker-compose.yml` defines the database and pg_bouncer services
1. `docker-compose.override.yml` defines the development flask web app
1. `docker-compose.prod.yml` defines the production flask web app served by nginx

Your tasks are to:

1. Modify the `docker-compose.override.yml` file so that the port exposed by the flask service is different.

1. Run the script `scripts/create_passwords.sh` to generate a new production password for the database.

1. Build and bring up the docker containers.

1. Enable ssh port forwarding so that your local computer can connect to the running flask app.

1. Use firefox on your local computer to connect to the running flask webpage.
   If you've done the previous steps correctly,
   all the buttons on the webpage should work without giving you any error messages,
   but there won't be any data displayed when you search.

1. Run the script
   ```
   $ sh scripts/check_web_endpoints.sh
   ```
   to perform automated checks that the system is running correctly.
   All tests should report `[pass]`.

## Task 2: loading data

There are two services for loading data:
1. `downloader_warc` loads an entire WARC file into the database; typically, this will be about 100,000 urls from many different hosts. 
1. `downloader_host` searches the all WARC entries in either the common crawl or internet archive that match a particular pattern, and adds all of them into the database

### Task 2a

We'll start with the `downloader_warc` service.
There are two important files in this service:
1. `services/downloader_warc/downloader_warc.py` contains the python code that actually does the insertion
1. `downloader_warc.sh` is a bash script that starts up a new docker container connected to the database, then runs the `downloader_warc.py` file inside that container

Next follow these steps:
1. Visit https://commoncrawl.org/the-data/get-started/
1. Find the url of a WARC file.
   On the common crawl website, the paths to WARC files are referenced from the Amazon S3 bucket.
   In order to get a valid HTTP url, you'll need to prepend `https://commoncrawl.s3.amazonaws.com/` to the front of the path.
1. Then, run the command
   ```
   $ ./downloader_warc.sh $URL
   ```
   where `$URL` is the url to your selected WARC file.
1. Run the command
   ```
   $ docker ps
   ```
   to verify that the docker container is running.
1. Repeat these steps to download at least 5 different WARC files, each from different years.
   Each of these downloads will spawn its own docker container and can happen in parallel.

You can verify that your system is working with the following tasks.
(Note that they are listed in order of how soon you will start seeing results for them.)
1. Running `docker logs` on your `downloader_warc` containers.
1. Run the query
   ```
   SELECT count(*) FROM metahtml;
   ```
   in psql.
1. Visit your webpage in firefox and verify that search terms are now getting returned.

### Task 2b

The `downloader_warc` service above downloads many urls quickly, but they are mostly low-quality urls.
For example, most URLs do not include the date they were published, and so their contents will not be reflected in the ngrams graph.
In this task, you will implement and run the `downloader_host` service for downloading high quality urls.

1. The file `services/downloader_host/downloader_host.py` has 3 `FIXME` statements.
   You will have to complete the code in these statements to make the python script correctly insert WARC records into the database.

   HINT:
   The code will require that you use functions from the cdx_toolkit library.
   You can find the documentation [here](https://pypi.org/project/cdx-toolkit/).
   You can also reference the `downloader_warc` service for hints,
   since this service accomplishes a similar task.

1. Run the query
   ```
   SELECT * FROM metahtml_test_summary_host;
   ```
   to display all of the hosts for which the metahtml library has test cases proving it is able to extract publication dates.
   Note that the command above lists the hosts in key syntax form, and you'll have to convert the host into standard form.
1. Select 5 hostnames from the list above, then run the command
   ```
   $ ./downloader_host.sh "$HOST"
   ```
   to insert the urls from these 5 hostnames.

## ~~Task 3: speeding up the webpage~~

Since everyone seems pretty overworked right now,
I've done this step for you.

There are two steps:
1. create indexes for the fast text search
1. create materialized views for the `count(*)` queries

## Submission

1. Edit this README file with the results of the following queries in psql.
   The results of these queries will be used to determine if you've completed the previous steps correctly.

    1. This query shows the total number of webpages loaded:
       ```
       select count(*) from metahtml;
       ```
       ``` 
        count  
        --------
         244801
        (1 row)
       
       ```
    1. This query shows the number of webpages loaded / hour:
       ```
       select * from metahtml_rollup_insert order by insert_hour desc limit 100;
       ```
       
       ``` 
         hll_count |  url   | hostpathquery | hostpath |  host  |      insert_hour       
        -----------+--------+---------------+----------+--------+------------------------
         2 |    892 |           873 |      873 |      2 | 2021-05-05 06:00:00+00
         3 |  21804 |         21523 |    21435 |  16419 | 2021-05-05 05:00:00+00
         4 | 134492 |        132408 |   131009 | 100485 | 2021-05-05 04:00:00+00
         2 |  34353 |         34846 |    33866 |  29269 | 2021-05-05 02:00:00+00
         2 |  51009 |         50675 |    50356 |  44145 | 2021-05-05 01:00:00+00
        (5 rows)
       ```

    1. This query shows the hostnames that you have downloaded the most webpages from:
       ```
       select * from metahtml_rollup_host2 order by hostpath desc limit 100;
       ```
       
    ```
                url | hostpathquery | hostpath |              host               
    -----+---------------+----------+---------------------------------
    591 |           573 |      573 | com,antiwar)
    299 |           301 |      301 | com,thebigsmoke)
    67 |            67 |       67 | com,smugmug,photos)
    31 |            31 |       31 | jp,ne,goo,blog)
    31 |            31 |       31 | com,ezlocal)
    30 |            30 |       30 | org,finra,brokercheck)
    29 |            29 |       29 | com,librarything,br)
    25 |            25 |       25 | com,freerepublic)
    23 |            23 |       23 | me,about)
    22 |            22 |       22 | jp,atwiki)
    22 |            22 |       22 | com,sulekha,property)
    22 |            22 |       22 | edu,illinois,carli,collections)
    22 |            22 |       22 | nl,leidenuniv,video)
    21 |            21 |       21 | ca,indigo,chapters)
    21 |            21 |       21 | com,motogp)
    21 |            21 |       21 | ru,ozon)
    21 |            21 |       21 | com,juegostin)
    21 |            21 |       21 | com,backyardchickens)
    20 |            20 |       20 | com,authorea)
    20 |            20 |       20 | tw,edu,pu,pufn113)
    20 |            20 |       20 | com,google,drive)
    20 |            20 |       20 | com,xiachufang)
    20 |            20 |       20 | jp,co,sharp,event)
    20 |            20 |       20 | com,mynewsdesk)
    20 |            20 |       20 | com,sherdog)
    19 |            19 |       19 | info,steamdb)
    19 |            19 |       19 | by,stroyka)
    19 |            19 |       19 | com,touristtube)
    19 |            19 |       19 | com,rediff,shopping)
    19 |            19 |       19 | com,movellas)
    19 |            19 |       19 | com,staticflickr,farm1)
    18 |            18 |       18 | com,microsoft,support)
    18 |            18 |       18 | com,cisco,cloudmgmt,docs)
    18 |            18 |       18 | io,steamid)
    18 |            18 |       18 | com,pinterest,fi)
    17 |            17 |       17 | us,or,state,osl,digital)
    17 |            17 |       17 | be,kuleuven,lirias)
    17 |            17 |       17 | ru,spb,brush)
    17 |            17 |       17 | com,staticflickr,farm2)
    17 |            17 |       17 | ru,crosti)
    17 |            17 |       17 | org,apache,mail-archives)
    17 |            17 |       17 | org,wikipedia,sv)
    17 |            17 |       17 | com,growkudos)
    17 |            17 |       17 | pl,zoover)
    17 |            17 |       17 | kz,gismeteo)
    17 |            17 |       17 | com,bandsintown)
    16 |            16 |       16 | com,msn)
    16 |            16 |       16 | org,ispotnature)
    16 |            16 |       16 | com,ipelican)
    16 |            16 |       16 | org,slideplayer)
    16 |            16 |       16 | ru,regnum)
    15 |            15 |       15 | jp,co,become)
    15 |            15 |       15 | org,doujinshi)
    15 |            15 |       15 | net,gutefrage)
    15 |            15 |       15 | com,17house)
    15 |            15 |       15 | com,coursehero)
    15 |            15 |       15 | org,kyvl,kdl)
    15 |            15 |       15 | es,vinted)
    15 |            15 |       15 | de,digitalfernsehen,forum)
    15 |            15 |       15 | com,grabcad)
    14 |            14 |       14 | com,bleacherreport)
    14 |            14 |       14 | com,123rf,fr)
    14 |            14 |       14 | com,funnyjunk)
    14 |            14 |       14 | ru,translate)
    14 |            14 |       14 | com,baddaddytube)
    14 |            14 |       14 | nl,slideplayer)
    14 |            14 |       14 | com,nifty,myhome)
    14 |            14 |       14 | com,elitetrader)
    14 |            14 |       14 | ru,trud)
    14 |            14 |       14 | nl,schlijper)
    14 |            14 |       14 | com,bhphotovideo)
    14 |            14 |       14 | com,office,support)
    14 |            14 |       14 | com,promodj)
    14 |            14 |       14 | com,colorhexa)
    13 |            13 |       13 | by,bestbooks)
    13 |            13 |       13 | com,chicagoparkdistrict)
    13 |            13 |       13 | com,kohls)
    13 |            13 |       13 | com,macworld)
    13 |            13 |       13 | ru,garant,base)
    13 |            13 |       13 | com,elpais)
    13 |            13 |       13 | com,causes)
    13 |            13 |       13 | com,vitals)
    13 |            13 |       13 | org,worldbank,documents)
    13 |            13 |       13 | de,wiwo)
    13 |            13 |       13 | ru,bananastreet)
    13 |            13 |       13 | org,wikipedia,ru)
    13 |            13 |       13 | com,businessinsider)
    13 |            13 |       13 | com,zuowen)
    13 |            13 |       13 | fr,bnf,data)
    13 |            13 |       13 | com,pocketmags)
    13 |            13 |       13 | com,gearbest)
    13 |            13 |       13 | ru,mybook)
    13 |            13 |       13 | com,hm)
    12 |            12 |       12 | jp,co,yahoo,gyao)
    12 |            12 |       12 | ua,com,look)
    12 |            12 |       12 | uk,co,foyles)
    12 |            12 |       12 | de,pinterest)
    12 |            12 |       12 | ua,zlato)
    12 |            12 |       12 | com,sputniknews,fr)
    12 |            12 |       12 | xyz,aparcel)
    (100 rows)
    ```

1. Take a screenshot of an interesting search result.
   Add the screenshot to your git repo, and modify the `<img>` tag below to point to the screenshot.

   
   <img width="634" alt="Screen Shot 2021-05-05 at 2 28 19 AM" src="https://user-images.githubusercontent.com/36056734/117108980-93462e00-ad49-11eb-88a6-a2dc420fc8a5.png">


1. Commit and push your changes to github.

1. Submit the link to your github repo in sakai.
