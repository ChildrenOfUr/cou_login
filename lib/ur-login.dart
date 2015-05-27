library login;

import 'dart:html';
import 'package:polymer/polymer.dart';
import 'package:firebase/firebase.dart';
import 'dart:async';
import 'dart:convert';

@CustomTag('ur-login')
class UrLogin extends PolymerElement {
  Firebase firebase;

  UrLogin.created() : super.created() {
    firebase = new Firebase("https://blinding-fire-920.firebaseio.com");


  }
}