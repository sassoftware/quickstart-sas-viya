/* just to test the reshift connection */

options sastrace='d,,d,d';
cas mysess sessopts=(caslib=casuser timeout=1800 locale="en_US");


proc cas;
    session mysess;
    action loadDatasource / name="redshift";
    run;
quit;

/* Create a CAS library that connects to the Redshift data source. */
proc cas;
  session mysess;
    action addCaslib / caslib="rslib"

                       datasource={srctype="redshift",
                                   server="ace-qs.cktnrp9lkl6c.us-east-1.redshift.amazonaws.com",
                                   database="dev",
                                   username="rsuser",
                                   password="RSAdminpw01"
                                   };
    run;
quit;
proc cas;
    session mysess;
    parms = {caslib="rslib"} ;
    action fileinfo result=r / parms ;
    print _status ;
    if (r.fileInfo.nrows > 0) then
        do i=1 to r.fileInfo.nrows ;
           put r.fileInfo[i];
       end;
    run;
quit;

cas mysess clear;