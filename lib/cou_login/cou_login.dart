import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:angular/angular.dart';
import 'package:angular/security.dart';
import 'package:angular_forms/angular_forms.dart';
import 'package:firebase/firebase.dart' as firebase;
import 'package:transmit/transmit.dart';

@Component(
    selector: 'cou-login',
    templateUrl: 'cou_login.html',
    styleUrls: [
      'cou_login.css',
    ],
    directives: const [coreDirectives, formDirectives],
)
class CouLogin {
    final DomSanitizationService _trustService;
    static List<String> greetingPrefixes = [
        // Displayed as: {greeting}, {username}
        "Good to see you",
        "Greetings",
        "Hello",
        "Hello there",
        "Have fun",
        "Hi",
        "Hi there",
        "It's good to see you",
        "Nice of you to join us",
        "Thanks for joining us",
        "Welcome",
        "Welcome back"
    ];

    String greetingPrefix = (greetingPrefixes..shuffle()).first;
    bool newUser = false;
    bool existingUser = false;
    bool forgotPassword = false;
    bool newSignup = false;
    bool passwordConfirmation = false;
    bool waiting = false;
    bool waitingOnEmail = false;
    bool resetStageTwo = false;
    bool timedout = false;
    String username = '';
    String newUsername = '';
    String email = '';
    String password = '';
    String confirmPassword = '';
    String newPassword = '';
    String tempPassword = '';
    String passwordWarning = '';
    String warningText = '';
    String server = 'https://server.childrenofur.com:8383';
    String websocket = 'ws://server.childrenofur.com:8484';
    String gameServer = 'https://server.childrenofur.com:8181';
    String _avatarUrl = 'packages/cou_login/cou_login/assets/player_unknown.png';
    num containerWidth,
        avatarWidth = 80,
        avatarHeight = 119;
    Map serverdata;
    firebase.User currentUser = null;
    firebase.Auth auth;

    CouLogin(this._trustService) : this.auth = firebase.auth() {
        auth.onAuthStateChanged.listen((firebase.User user) async {
            currentUser = user;
            if (currentUser != null) {
                fireLoginSuccess(await getSession(currentUser.email));
            } else {
                window.localStorage.remove('username');
            }
        });
    }

    SafeStyle get avatarUrl => _trustService.bypassSecurityTrustStyle('url(${_avatarUrl})');

    bool get loggedIn => currentUser != null;

    String get userEmail => auth.currentUser?.email;

    String get displayName => window.localStorage['username'];

    // If the provider gave us an access token, we put it here.
    String providerAccessToken = "";

    bool _enterKey(event) {
        //detect enter key
        return event is KeyboardEvent && event.keyCode == 13;
    }

    signOut() {
        auth.signOut();
        newUser = false;
        window.localStorage.remove('username');
    }

    loginAttempt(event) async {
        if (!_enterKey(event)) return;

        if (passwordConfirmation) {
            verifyEmail(event);
            return;
        }

        waiting = true;

        try {
            await auth.setPersistence('local');
            firebase.UserCredential credential =
            await auth.signInWithEmailAndPassword(email, password);
            document.dispatchEvent(
                new CustomEvent('loginSuccess', detail: 'Yay!'));
            Map sessionMap = await getSession(email);

            fireLoginSuccess(sessionMap);
            print('$email logged in successfully');
        } catch (err) {
            try {
                //check to see if they have already verified their email (game window was closed when they clicked the link)
                HttpRequest request = await HttpRequest.request(
                    server + "/auth/isEmailVerified",
                    method: "POST",
                    requestHeaders: {"content-type": "application/json"},
                    sendData: jsonEncode({'email': email}));
                Map map = jsonDecode(request.response);
                if (map['result'] == 'success') {
                    await _createNewUser(map);
                } else {
                    throw (err);
                }
            } catch (err) {
                //we've never seen them before or they haven't yet verified their email
                String error = err.toString();
                if (error.contains('Error: '))
                    error = error.replaceFirst('Error: ', '');
                warningText = error;
                //print(err);
            }
        } finally {
            waiting = false;
        }
    }

    Future<Map> getSession(String email) async {
        HttpRequest request = await HttpRequest.request(
            server + "/auth/getSession",
            method: "POST",
            requestHeaders: {"content-type": "application/json"},
            sendData: jsonEncode({'email': email}));
        window.localStorage['authEmail'] = currentUser.email;
        Map sessionMap = jsonDecode(request.response);
        if (sessionMap['playerName'] != '') {
            window.localStorage['username'] = sessionMap['playerName'];
        }

        return sessionMap;
    }

    usernameSubmit(event) async {
        if (!_enterKey(event)) {
            return;
        }

        if (newUsername == '') {
            return;
        }

        waiting = true;

        if (existingUser) {
            fireLoginSuccess(serverdata);
        } else {
            document
                .dispatchEvent(
                new CustomEvent('setUsername', detail: newUsername));
        }
    }

    verifyEmail(event) async {
        warningText = '';

        // not an email
        if (!email.contains('@')) {
            warningText = 'Invalid email';
            return;
        }

        // password too short
        if (password.length < 6) {
            warningText = 'Password too short';
            return;
        }

        // display password confirmation
        if (!passwordConfirmation) {
            passwordConfirmation = true;
            return;
        }

        // passwords don't match
        if (password != confirmPassword) {
            warningText = "Passwords don't match";
            return;
        }

        if (!_enterKey(event)) {
            return;
        }

        if (email == '') {
            return;
        }

        waiting = true;
        waitingOnEmail = true;

        HttpRequest request = await HttpRequest.request(
            "https://server.childrenofur.com:8383/auth/verifyEmail",
            method: "POST",
            requestHeaders: {"content-type": "application/json"},
            sendData: jsonEncode({'email': email}));

        Map result = jsonDecode(request.response);
        if (result['result'] != 'OK') {
            waiting = false;
            print(result);
            return;
        }

        WebSocket ws = new WebSocket(websocket + "/awaitVerify");
        ws.onOpen.first.then((_) {
            Map map = {'email': email};
            ws.send(jsonEncode(map));
        });
        ws.onMessage.first.then((MessageEvent event) async {
            Map map = jsonDecode(event.data);
            if (map['result'] == 'success') {
                await _createNewUser(map);
            } else {
                print('problem verifying email address: ${map['result']}');
            }

            waiting = false;
        });
    }

    Future _createNewUser(Map map) async {
        try {
            //create the user in firebase
            await auth.createUserWithEmailAndPassword(email, password);

            newPassword = password;
            if (map['serverdata']['playerName'].trim() != '') {
                username = map['serverdata']['playerName'].trim();
                window.localStorage['username'] = username;
                //email already exists, make them choose a password
                existingUser = true;
            } else {
                newUser = true;
                newUsername = username;
                await auth.signInWithEmailAndPassword(email, password);
                window.localStorage['authEmail'] =
                map['serverdata']['playerEmail'];
                serverdata = map['serverdata'];
                print('new user');
            }
            fireLoginSuccess(map['serverdata']);
        } catch (err) {
            print("couldn't create user on firebase: $err");
        }
    }

    oauthLogin(String provider) async {
        firebase.AuthProvider authProvider;
        if (provider == 'facebook') {
            authProvider = firebase.FacebookAuthProvider();
            (authProvider as firebase.FacebookAuthProvider).addScope('email');
        } else if (provider == 'github') {
            authProvider = firebase.GithubAuthProvider();
            (authProvider as firebase.GithubAuthProvider).addScope('user:email');
        } else if (provider == 'google') {
            authProvider = firebase.GoogleAuthProvider();
            (authProvider as firebase.GoogleAuthProvider).addScope('email');
        }

        waiting = true;
        try {
            firebase.UserCredential credential =
            await auth.signInWithPopup(authProvider);

            String email;
            if (provider == 'google' || provider == 'facebook') {
                email = credential.additionalUserInfo.profile['email'];
            } else if (provider == 'github') {
                email = credential.user.providerData[0].email;
            }
            print('user logged in with $provider: ${email}');
            Map sessionMap = await getSession(email);
            if (sessionMap['playerName'] == '') {
                newUser = true;
            } else {
                fireLoginSuccess(sessionMap);
            }
        } catch (err) {
            print('failed login with $provider: $err');
        } finally {
            waiting = false;
        }
    }

    fireLoginSuccess(var payload) async {
        Timer acknowledgeTimer;
        new Service(['loginAcknowledged'], (m) {
            //print('canceling success repeater');
            acknowledgeTimer.cancel();
        });
        acknowledgeTimer =
        new Timer.periodic(new Duration(seconds: 1), (Timer t) {
            document.dispatchEvent(
                new CustomEvent('loginSuccess', detail: payload));
        });
        document.dispatchEvent(
            new CustomEvent('loginSuccess', detail: payload));
    }

    togglePassword() {
        forgotPassword = !forgotPassword;
        resetStageTwo = false;
    }

    updateAvatarPreview() {
        // Provide a default
        if (newUsername == "") {
            newUsername = "ellelament";
        }
        // $server = http|//hostname|8383 (| = split point)
        //           ^  +     ^    (-  ^)
        HttpRequest.getString(
            "$gameServer/getSpritesheets?username=$newUsername")
            .then((String json) {
            _avatarUrl = jsonDecode(json)["base"];
            // Used for sizing
            ImageElement avatarData = new ImageElement()
                ..src = _avatarUrl;
            // Resize elements to fit image
            avatarData.onLoad.listen((_) {
                containerWidth = avatarData.naturalWidth / 15;
                avatarWidth = avatarData.naturalWidth;
                avatarHeight = avatarData.naturalHeight;
            });
        });
    }

    resetPassword() async {
        if (!resetStageTwo) {
            auth.sendPasswordResetEmail(email);
            resetStageTwo = true;
            return;
        } else {
            if (newPassword != confirmPassword) {
                passwordWarning = "Passwords don't match";
                return;
            }

            try {
                await auth.confirmPasswordReset(tempPassword, newPassword);
                togglePassword();
            } catch (error) {
                print(error);
            }
        }
    }
}