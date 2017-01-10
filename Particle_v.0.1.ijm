/**
* Macro to analyze passive particle monitor samples
*
*@author Simon Pyle
*@author https://publiclab.org/profile/SimonPyle
*@author info@simonpyle.com
*@version 0.1
*@licensed under GNU GPLv3
*/

//starting variables
validImageTypes = newArray('tif', 'tiff', 'jpg', 'jpeg', 'bmp', 'fits', 'pgm', 'ppm', 'pbm','gif', 'png', 'jp2','psd');
run("Clear Results"); //ensure that we're starting with a blank results table

//OS X 10.11 (El Capitan) removes the title bar from file/directory open dialogs
//Use JFileChoose as a workaround
//http://fiji.sc/bugzilla/show_bug.cgi?id=1188
setOption("JFileChooser", true);

inputDirectory = getDirectory("Choose a directory with images to analyze:");

//Options dialog
Dialog.create("Set options");
items = newArray("Use flatfield microscope image for image correction", 
	"Create a psuedo-flat-field image for image correction","No image correction");
Dialog.addRadioButtonGroup("Image Correction", items, 3, 1, "No image correction");
Dialog.addCheckbox("Extract blue channel for analysis",false);
Dialog.addChoice("Scale calibration:", newArray("Measure image of stage micrometer scale", "Enter numeric scale value"));
Dialog.addCheckbox("Crop images to remove vignetting", false);
Dialog.addCheckbox("Hide images when processing? (faster)", false);
Dialog.show();

correctionTechnique = Dialog.getRadioButton();
useCalibrationImage = false;
usePseudoCalibrationImage = false;
if(correctionTechnique=="Create a psuedo-flat-field image for image correction"){
	usePseudoCalibrationImage = true;
} else if(correctionTechnique=="Use flatfield microscope image for image correction"){
	useCalibrationImage = true;
}
extractBlueChannel = Dialog.getCheckbox();
scaleChoice = Dialog.getChoice();
if (scaleChoice == "Enter numeric scale value"){
	measureScale = false;
} else {
	measureScale = true;
}
needCrop = Dialog.getCheckbox();
batchMode = Dialog.getCheckbox();
IJ.log("Options:");
IJ.log("Correction technique = " + correctionTechnique);
IJ.log("Flatfield correction = " + useCalibrationImage); 
IJ.log("Pseudo Flatfield = " + usePseudoCalibrationImage); 
IJ.log("Extract Blue Channel = " + extractBlueChannel);
if(measureScale){
	IJ.log("Enter numeric scale = " + measureScale);
} else {
	IJ.log("Measure scale from slide = " + measureScale+1);
}
IJ.log("Crop images = " + needCrop);
IJ.log("BatchMode = " + batchMode);
	

//Choosing a flatfield image for calibration
if (useCalibrationImage) {
	calibrationImagePath = File.openDialog("Select the flatfield microscope image:");
	open(calibrationImagePath);
	//calibrationImageID = getImageID(); //This doesn't seem to be used - referring by title instead.
	calibrationImageTitle = getTitle();
	run("Set Measurements...", "mean redirect=None decimal=3");
	run("Select All");
	run("Measure");
	flatfieldMean = getResult("Mean");
	//We don't close() this image because it's used later by the calculator
	
}
if(usePseudoCalibrationImage){
	Dialog.create("Enter radius value for averaging image");
	Dialog.addNumber("mean radius value for pseudofield", 150);
	Dialog.show();
	radius = Dialog.getNumber();
}
//Calculating the image scale
if (measureScale) {
	rulerImagePath = File.openDialog("Select an image with a calibration ruler for these images:");
	open(rulerImagePath);
	setTool("line");
	waitForUser("Draw a line between two points of a known distance.\nClick OK when done.");
	getLine(x1, y1, x2, y2, lineWidth);
	while (x1==-1) {//x1 = -1 if there is no line selection
		waitForUser("Calibration requires a straight line selection.\nDraw a line between two points of a known distance.\nClick OK when done.");
		getLine(x1, y1, x2, y2, lineWidth);
	}
	Dialog.create("Enter known distance and units");
	Dialog.addNumber("Known distance:", 50);
	Dialog.addString("Units:", "um");
	Dialog.show();
	knownLength = Dialog.getNumber();
	print("knownLength = " + knownLength);
	distanceUnits = Dialog.getString(); //measurement units that are the denominator of the scale, i.e. pixels/unit
	run("Set Scale...", "known=&knownLength unit=&distanceUnits global"); //global only refers to currently open images?
	close();
	//We also calculate the scale separately because I can't figure out how to return the scale value 
	//from 'run("Set Scale...")' as a variable.
	dx = x2-x1; dy = y2-y1;
	measuredLength = sqrt(dx*dx+dy*dy);
	IJ.log("Length:" +  measuredLength + "pixels");
	} else {
	//If not measuring, include an option to enter in a scale value.
	Dialog.create("Enter scale values");
	Dialog.addNumber("Pixels", 1);
	Dialog.addNumber("per known measurement length", 1);
	Dialog.addString("measurement units ", "um");
	Dialog.show();
	measuredLength = Dialog.getNumber();
	knownLength = Dialog.getNumber();
	distanceUnits = Dialog.getString();
	}
//common settings of scale variables to both measurement and direct entry
scale = (measuredLength / knownLength); //The scale is pixels per known measurement
IJ.log("Scale = " + scale + " pixels per " + distanceUnits);
scaleUnits = "pixels per " + distanceUnits;
IJ.log(scaleUnits);
	
//Choosing the area to crop
if (needCrop){
	cropImagePath = File.openDialog("Select a typical image to select the crop area for all images");
	open(cropImagePath);
	setTool("rectangle");
	waitForUser("Select the area to crop. \nClick OK when done.");
	getSelectionBounds(xCrop, yCrop, widthCrop, heightCrop);
	close();
}

//Create a new directory for the results of analysis with a timestamped name to reduce possibility 
//of overwriting multiple runs of macro
parent = File.getParent(inputDirectory);
strippedDir = substring(inputDirectory,0,lengthOf(inputDirectory)-1); 
	//removes the trailing slash from the parent directory 
//Output directory name is: imageDirectory_results_year_monthday_hourminutesecond
getDateAndTime(year,month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
MonthNames = newArray("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
timeStamp = d2s(year,0)+"_"+MonthNames[month]+"_"+d2s(dayOfMonth,0)+"_"+d2s(hour,0)+"h"
			+d2s(minute,0)+"m"+d2s(second,0)+"s";
outputDirectory = strippedDir + "_results_"+timeStamp;

//If the directory already exists, append to the name until it's a unique directory
while (File.exists(outputDirectory)) { 
	outputDirectory = outputDirectory + "_2";
}
File.makeDirectory(outputDirectory);
if (!File.exists(outputDirectory)) {
	exit("Could not create output directory " + outputDirectory);
}

//Get list of images in directory, ignoring files with other extensions
fileList = getFileList(inputDirectory);
Array.print(fileList);
imageNames = newArray();
for (i=0; i<fileList.length-1; i++) {
	fileName = fileList[i];
	for (j=0; j<validImageTypes.length; j++) {
		if (endsWith(fileName, validImageTypes[j])) {
			imageNames = Array.concat(imageNames, fileName);
		}
	}
}

// Set a path for the results csv
resultsPath = outputDirectory + File.separator + "results.csv";
print("results will be saved to " + resultsPath);
areaTallyPath = outputDirectory + File.separator + "area.csv";

//iterate through the image list
imageCount = 0;
totalPixelArea = 0;
setBatchMode(batchMode); 
for (i=0; i<imageNames.length-1; i++) {
	saveCount = 0;
	IJ.log("image #: " + i+1);
	IJ.log(imageNames[i]);
	fileName = imageNames[i]; 
	filePath = inputDirectory + fileName;
	open(filePath);
	print("Analyzing " + filePath);
	outputFilePath = outputDirectory + File.separator + fileName;
	sampleImageTitle = getTitle();

	//apply calibration, if available, using the procedure here: 
	//http://imagej.net/Image_Intensity_Processing
	if(useCalibrationImage) { 
		IJ.log("Dividing " + sampleImageTitle + " / " + calibrationImageTitle);
		run("Calculator Plus", "i1=&sampleImageTitle i2=&calibrationImageTitle operation=[Divide: i2 = (i1/i2) x k1 + k2] k1=&flatfieldMean k2=0 create");
		saveImageStep(outputFilePath, saveCount, "Flatfield_calibrated");
		saveCount++;
	}
	if(extractBlueChannel) {
		run("Split Channels"); 
		saveImageStep(outputFilePath, saveCount, "Blue_channel_only");
		sampleImageTitle = getTitle();
		//This relies on the fact that the blue channel image is on top post-split
		saveCount++;
	}
	if(usePseudoCalibrationImage) {
		run("Duplicate...", "title="+sampleImageTitle+"_pseudofield");
		pseudofieldImageTitle = getTitle();
		run("Mean...", "radius=&radius");
		imageCalculator("Subtract create", pseudofieldImageTitle,sampleImageTitle);
		run("Invert");
		saveImageStep(outputFilePath, saveCount, "Pseudo_corrected");
		saveCount++;
		//TODO - do this for every channel and then recombine?
	}
	if(needCrop){
		makeRectangle(xCrop, yCrop, widthCrop, heightCrop);
		run("Crop");
		saveImageStep(outputFilePath, saveCount, "crop");
		saveCount++;	
	}
	run("8-bit");
	saveImageStep(outputFilePath, saveCount, "8bit");
	saveCount++;
	run("Auto Threshold", "method=Yen white");
	saveImageStep(outputFilePath, saveCount, "Threshold");
	saveCount++;
	setOption("BlackBackground", false);
	run("Make Binary");
	saveImageStep(outputFilePath, saveCount, "Binary");
	saveCount++;
	run("Fill Holes");
	saveImageStep(outputFilePath, saveCount, "FilledHoles");
	saveCount++;
	run("Set Measurements...", "area perimeter shape display redirect=None decimal=3");
	run("Set Scale...", "distance=&measuredLength known=&knownLength unit=&distanceUnits global");
	run("Analyze Particles...", "show=Outlines display"); //appends results to existing results window
	saveImageStep(outputFilePath, saveCount, "ParticleCounts");
	saveCount++;

	//keep track of the image area analyzed
	getDimensions(imageWidth, imageHeight,channels,slices,frames);
	IJ.log("Width = " + imageWidth + " Height = " + imageHeight);
	imagePixelArea = imageWidth * imageHeight;
	IJ.log("Image pixel area = " + imagePixelArea);
	imageCount = i+1;
	totalPixelArea = totalPixelArea + imagePixelArea;
	IJ.log("Running count of total pixel area = " + totalPixelArea);

	//cleaning up by closing open images
	closeCount = 2; //original image & image created by "Analyze Particles"
	if(usePseudoCalibrationImage){
		closeCount++;//pseudo flatfield creates 1 new window
	}
	if(extractBlueChannel){
		closeCount = closeCount+3; //split channels creates 3 new windows
	}
	for(k=1; k<=closeCount; k++){
		close();
	}

/*	This is a way to close every image (but not results or log windows)
	close("\\Others"); //closes every image but the front window
	close();
*/	
}

saveAs("results", resultsPath);
areaFile = File.open(areaTallyPath);
print(areaFile, "Number of images analyzed," + imageCount);
print(areaFile, "Width of last image analyzed," + imageWidth + ",pixels wide");
print(areaFile, "Height of last image analyzed," + imageHeight + ",pixels high");
print(areaFile, "Area of last image analyzed," + imageWidth*imageHeight + ",pixels");
print(areaFile, "Average area of all images analyzed," + totalPixelArea/imageCount + ",pixels");
	//these measurements included just as a sanity check
print(areaFile, "Total Pixel Area of all images," + totalPixelArea + ",pixels^2");
print(areaFile, "Scale," + scale + "," + scaleUnits); //scale units is pixels per length
print(areaFile, "Scale," + scale*scale + ",pixels per " + distanceUnits + "^2"); 
print(areaFile, "Total Analyzed Area," + (totalPixelArea / (scale*scale)) + "," + distanceUnits + "^2");
print(areaFile, "Note: this macro assumes square pixels");



function saveImageStep(filePath, saveCount, stepName){
	path = filePath + "_step" + saveCount+ "_" + stepName;
	//may need to insert name before the extension
	save(path);
	IJ.log("saved to " + path);
}

