// ignore_for_file: library_prefixes, library_private_types_in_public_api, avoid_print, use_build_context_synchronously, unnecessary_null_comparison, avoid_unnecessary_containers

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart' as fStorage;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../global/global.dart';
import '../mainScreens/home_screen.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/error_dialog.dart';
import '../widgets/loading_dialog.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  TextEditingController nameController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController confirmPasswordController = TextEditingController();
  TextEditingController phoneController = TextEditingController();
  TextEditingController locationController = TextEditingController();

  XFile? imageXFile;
  final ImagePicker _picker = ImagePicker();

  Position? position;
  List<Placemark>? placeMarks;

  String sellerImageUrl = "";
  String completeAddress = "";

  Future<void> _getImage() async {
    imageXFile = await _picker.pickImage(source: ImageSource.gallery);
    setState(() {
      imageXFile;
    });
  }

  Future<void> getCurrentLocation() async {
    Position? newPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    if (newPosition != null) {
      position = newPosition;

      placeMarks = await placemarkFromCoordinates(
        position!.latitude,
        position!.longitude,
      );

      if (placeMarks != null && placeMarks!.isNotEmpty) {
        Placemark pMark = placeMarks![0];

        completeAddress =
            '${pMark.subThoroughfare} ${pMark.thoroughfare}, ${pMark.subLocality} ${pMark.locality}, ${pMark.subAdministrativeArea}, ${pMark.administrativeArea} ${pMark.postalCode}, ${pMark.country}';

        locationController.text = completeAddress;
      } else {
        // Handle the case where reverse geocoding didn't return any results
        print("Reverse geocoding didn't return any results.");
      }
    } else {
      // Handle the case where newPosition is null
      print("Location retrieval failed.");
    }
  }

  Future<void> requestLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      // Location permission granted, proceed to get the location
      getCurrentLocation();
    } else {
      // Location permission denied, show a message to the user
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
              'Please grant location permission to use this feature.'),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }

  Future<void> formValidation() async {
    if (imageXFile == null) {
      showDialog(
          context: context,
          builder: (c) {
            return ErrorDialog(
              message: "Please select an image.",
            );
          });
    } else {
      if (passwordController.text == confirmPasswordController.text) {
        if (confirmPasswordController.text.isNotEmpty &&
            emailController.text.isNotEmpty &&
            nameController.text.isNotEmpty &&
            phoneController.text.isNotEmpty &&
            locationController.text.isNotEmpty) {
          //start uploading image
          showDialog(
            context: context,
            builder: (c) {
              return LoadingDialog(
                message: "Registering Account",
              );
            },
          );

          String fileName = DateTime.now().millisecondsSinceEpoch.toString();
          fStorage.Reference reference = fStorage.FirebaseStorage.instance
              .ref()
              .child("sellers")
              .child(fileName);
          fStorage.UploadTask uploadTask =
              reference.putFile(File(imageXFile!.path));
          fStorage.TaskSnapshot taskSnapshot =
              await uploadTask.whenComplete(() {});
          await taskSnapshot.ref.getDownloadURL().then((url) {
            sellerImageUrl = url;

            //save info to firestore
            authenticateSellerAndSignUp();
          });
        } else {
          showDialog(
              context: context,
              builder: (c) {
                return ErrorDialog(
                  message:
                      "Please write the complete required info for Registration.",
                );
              });
        }
      } else {
        showDialog(
            context: context,
            builder: (c) {
              return ErrorDialog(
                message: "Password do not match.",
              );
            });
      }
    }
  }

  void authenticateSellerAndSignUp() async {
    User? currentUser;

    await firebaseAuth
        .createUserWithEmailAndPassword(
      email: emailController.text.trim(),
      password: passwordController.text.trim(),
    )
        .then(
      (auth) {
        currentUser = auth.user;
      },
    ).catchError(
      (error) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (c) {
            return ErrorDialog(
              message: error.message.toString(),
            );
          },
        );
      },
    );

    if (currentUser != null) {
      saveDataToFirestore(currentUser!).then(
        (value) {
          Navigator.pop(context);

          // Send user to HomePage...
          Route newRoute =
              MaterialPageRoute(builder: (c) => const HomeScreen());
          Navigator.pushReplacement(context, newRoute);
        },
      );
    }
  }

  Future<void> saveDataToFirestore(User currentUser) async {
    try {
      await FirebaseFirestore.instance
          .collection("sellers")
          .doc(currentUser.uid)
          .set({
        "sellerUID": currentUser.uid,
        "sellerEmail": currentUser.email,
        "sellerName": nameController.text.trim(),
        "sellerAvatarUrl": sellerImageUrl,
        "phone": phoneController.text.trim(),
        "address": completeAddress,
        "status": "approved",
        "earnings": 0.0,
        "lat": position!.latitude,
        "lng": position!.longitude,
      });

      // Save data locally
      sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences!.setString("uid", currentUser.uid);
      await sharedPreferences!.setString("email", currentUser.email.toString());
      await sharedPreferences!.setString("name", nameController.text.trim());
      await sharedPreferences!.setString("photoUrl", sellerImageUrl);

      print(sharedPreferences!.getString("name"));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Congratulations, your account has been created."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print("Error saving data: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ),
      );
      // You can display an error message to the user if needed.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            const SizedBox(
              height: 10,
            ),
            InkWell(
              onTap: () {
                _getImage();
              },
              child: CircleAvatar(
                radius: MediaQuery.of(context).size.width * 0.20,
                backgroundColor: Colors.white,
                backgroundImage: imageXFile == null
                    ? null
                    : FileImage(File(imageXFile!.path)),
                child: imageXFile == null
                    ? Icon(
                        Icons.add_photo_alternate,
                        size: MediaQuery.of(context).size.width * 0.20,
                        color: Colors.grey,
                      )
                    : null,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  CustomTextField(
                    data: Icons.person,
                    controller: nameController,
                    hintText: "Name",
                    isObsecre: false,
                  ),
                  CustomTextField(
                    data: Icons.email,
                    controller: emailController,
                    hintText: "Email",
                    isObsecre: false,
                  ),
                  CustomTextField(
                    data: Icons.lock,
                    controller: passwordController,
                    hintText: "Password",
                    isObsecre: true,
                  ),
                  CustomTextField(
                    data: Icons.lock,
                    controller: confirmPasswordController,
                    hintText: "Confirm Password",
                    isObsecre: true,
                  ),
                  CustomTextField(
                    data: Icons.phone,
                    controller: phoneController,
                    hintText: "Phone",
                    isObsecre: false,
                  ),
                  CustomTextField(
                    readOnly: true,
                    data: Icons.my_location,
                    controller: locationController,
                    hintText: "Cafe/Restaurant Address",
                    isObsecre: false,
                    enabled: true,
                  ),
                  Container(
                    width: 400,
                    height: 40,
                    alignment: Alignment.center,
                    child: ElevatedButton.icon(
                      label: const Text(
                        "Get my Current Location",
                        style: TextStyle(color: Colors.white),
                      ),
                      icon: const Icon(
                        Icons.location_on,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        requestLocationPermission();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(
              height: 30,
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                padding:
                    const EdgeInsets.symmetric(horizontal: 50, vertical: 10),
              ),
              onPressed: () {
                formValidation();
              },
              child: const Text(
                "Sign Up",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(
              height: 30,
            ),
          ],
        ),
      ),
    );
  }
}
