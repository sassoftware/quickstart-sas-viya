/**
* A Lambda function that looks up the latest AMI ID for a given region and architecture.
**/

"use strict";

var Adm = require('adm-zip');
var Aws = require("aws-sdk");
var Fs = require("fs");

// Map instance architectures to an AMI name pattern
var archToAMINamePattern = {
    "AMZNLINUXHVM": "amzn-ami-hvm*x86_64-gp2",
    "RHEL74HVM": "RHEL-7.4_HVM_GA*-Hourly2-GP2"
};



exports.license = function(event, context) {

    console.log("REQUEST RECEIVED:\n" + JSON.stringify(event));

    // For Delete requests, immediately send a SUCCESS response.
    if (event.RequestType == "Delete") {
        sendResponse(event, context, "SUCCESS");
        return;
    }

    var responseStatus = "FAILED";
    var responseData = {};

    var s3 = new Aws.S3();

    var ddl = event.ResourceProperties.DeploymentDataLocation

    var options = {
        Bucket : ddl.substr(0,ddl.indexOf('/')),
        Key    : ddl.substr(ddl.indexOf('/')+1),
    };

    var tempzip = '/tmp/temp.zip';
    var templicensefile = '/tmp/license.txt';


    // read s3 file and write out to file
    s3.getObject(options).createReadStream().pipe(Fs.createWriteStream(tempzip)).on('finish', function()  {

       var unzip = new Adm(tempzip);

       unzip.getEntries().forEach(function(zipEntry) {

            // license file name: SASViyaV0300_*_Linux_x86-64.txt
            if ('licenses/' ==  zipEntry.entryName.substring(0,9)) {
                console.log(zipEntry.entryName);

                Fs.writeFile(templicensefile, unzip.readAsText(zipEntry));

                var lineReader = require('readline').createInterface({
                    input: Fs.createReadStream(templicensefile)
                });

                var lf = [];
                var tline = '';

                lineReader.on('line', function (line) {
                    // unwrap lines
                    tline = tline + line;
                    if (tline.slice(-1) == ';') {
                        lf.push(tline);
                        tline = '';
                    }
                }).on('close', function() {
                    // extract cpu count for cas

                    // get line with cpu for cas product number (e.g. EXPIRE 'PRODNUM1141' '31MAY2018'D / CPU=CPU001;)
                    let prodnum = lf.filter(s => s.includes('EXPIRE')).filter(s => s.includes('PRODNUM1141'));
                    if (prodnum.length != 1)  return console.error("PRODNUM1141 = "+prodnum.length );

                    // get name of cas cpu
                    var cascpu = prodnum[0].substring(prodnum[0].indexOf("CPU=")+4,prodnum[0].indexOf(';'));
                    if (cascpu.length == 0) return console.error("CASCPU = "+cascpu.length );

                    // get line with CASCPU (e.g.  CPU MODEL=' ' MODNUM=' ' SERIAL='+16' NAME=CPU001;)
                    var model = lf.filter(s => s.includes("NAME="+cascpu))
                    if (model.length != 1) return console.error("Model = "+model.length );

                    // extract cpu count
                    var cpucount = model[0].match('\\+[0-9][0-9]*');
                    cpucount = cpucount[0].replace('+',"");

                    responseStatus = "SUCCESS";
                    responseData["CPUCount"] = cpucount;

                    if (cpucount == 4) {
                         responseData["NodeInstanceSize"] = "2xlarge";
                         responseData["NumWorkers"] = 0;
                    } else if (cpucount <= 8) {
                         responseData["NodeInstanceSize"] = "4xlarge";
                         responseData["NumWorkers"] = 0;
                    } else if (cpucount <= 16) {
                         responseData["NodeInstanceSize"] = "8xlarge";
                         responseData["NumWorkers"] = 0;
                    } else if (cpucount <= 32) {
                         responseData["NodeInstanceSize"] = "16xlarge";
                         responseData["NumWorkers"] = 0;
                    } else if (cpucount <= 64) {
                         responseData["NodeInstanceSize"] = "8xlarge";
                         responseData["NumWorkers"] = 3;
                    } else if (cpucount <= 128) {
                         responseData["NodeInstanceSize"] = "16xlarge";
                         responseData["NumWorkers"] = 3;
                    } else {
                         responseStatus = "FAILED";
                         console.error("Invalid Licensed CPU Count: ", cpucount);
                    }

                    console.log("ResponseData: " + JSON.stringify(responseData));

                    sendResponse(event, context, responseStatus, responseData);
               });
            }
        });
   });
};

exports.amilookup = function(event, context) {

    console.log("REQUEST RECEIVED:\n" + JSON.stringify(event));

    // For Delete requests, immediately send a SUCCESS response.
    if (event.RequestType == "Delete") {
        sendResponse(event, context, "SUCCESS");
        return;
    }

    var responseStatus = "FAILED";
    var responseData = {};

    var ec2 = new Aws.EC2({region: event.ResourceProperties.Region});
    var describeImagesParams = {
        Filters: [{ Name: "name", Values: [archToAMINamePattern[event.ResourceProperties.Architecture]]}],
        Owners: [event.ResourceProperties.Architecture == "RHEL74HVM" ? "309956199498" : "amazon"]
    };

    // Get AMI IDs with the specified name pattern and owner
    ec2.describeImages(describeImagesParams, function(err, describeImagesResult) {
        if (err) {
            responseData = {Error: "DescribeImages call failed"};
            console.log(responseData.Error + ":\n", err);
        }
        else {
            var images = describeImagesResult.Images;
            // Sort images by name in decscending order. The names contain the AMI version, formatted as YYYY.MM.Ver.
            images.sort(function(x, y) { return y.Name.localeCompare(x.Name); });
            for (var j = 0; j < images.length; j++) {
                if (isBeta(images[j].Name)) continue;
                responseStatus = "SUCCESS";
                responseData["Id"] = images[j].ImageId;
                console.log("IMAGEDETAIL:\n" + JSON.stringify(images[j]));
                break;
            }
        }
        sendResponse(event, context, responseStatus, responseData);
    });
};

// Check if the image is a beta or rc image. The Lambda function won't return any of those images.
function isBeta(imageName) {
    return imageName.toLowerCase().indexOf("beta") > -1 || imageName.toLowerCase().indexOf(".rc") > -1;
}


// Send response to the pre-signed S3 URL
function sendResponse(event, context, responseStatus, responseData) {

    var responseBody = JSON.stringify({
        Status: responseStatus,
        Reason: "See the details in CloudWatch Log Stream: " + context.logStreamName,
        PhysicalResourceId: context.logStreamName,
        StackId: event.StackId,
        RequestId: event.RequestId,
        LogicalResourceId: event.LogicalResourceId,
        Data: responseData
    });

    console.log("RESPONSE BODY:\n", responseBody);

    var https = require("https");
    var url = require("url");

    var parsedUrl = url.parse(event.ResponseURL);
    var options = {
        hostname: parsedUrl.hostname,
        port: 443,
        path: parsedUrl.path,
        method: "PUT",
        headers: {
            "content-type": "",
            "content-length": responseBody.length
        }
    };

    console.log("SENDING RESPONSE...\n");

    var request = https.request(options, function(response) {
        console.log("STATUS: " + response.statusCode);
        console.log("HEADERS: " + JSON.stringify(response.headers));
        // Tell AWS Lambda that the function execution is done
        context.done();
    });

    request.on("error", function(error) {
        console.log("sendResponse Error:" + error);
        // Tell AWS Lambda that the function execution is done
        context.done();
    });

    // write data to request body
    request.write(responseBody);
    request.end();
}
