import 'package:angular/angular.dart';
import 'package:cou_login/cou_login/cou_login.template.dart' as ng;
import 'package:firebase/firebase.dart' as firebase; // ignore: uri_has_not_been_generated

void main() {
    firebase.initializeApp(
        apiKey: "AIzaSyCTXgszjO2AJNLTZUMYp2ZtFAmVLS2G6J4",
        authDomain: "blinding-fire-920.firebaseapp.com",
    );
    runApp(ng.CouLoginNgFactory);
}
