library login;

import 'dart:html';
import 'package:polymer/polymer.dart';
import 'package:firebase/firebase.dart';
import 'dart:async';
import 'dart:convert';
import 'package:transmit/transmit.dart';

@CustomTag('ur-login')
class UrLogin extends PolymerElement {
	@published String server, websocket, base;
	@observable bool newUser = false, forgotPassword = false, resetStageTwo = false, passwordConfirmation = false;
	@observable bool timedout = false, newSignup = false, waiting = false, invalidEmail = false;
	@observable bool waitingOnEmail = false, existingUser = false, loggedIn = false, passwordTooShort = false;
	@observable String newUsername = '', newPassword = '';
	Firebase firebase;
	Map serverdata;

	@observable String username = '';
	@observable String email = '';
	@observable String password = '';

	UrLogin.created() : super.created() {
		firebase = new Firebase("https://$base.firebaseio.com");
		if (window.localStorage.containsKey('username')) {
			//let's see if our firebase auth is current
			Map auth = firebase.getAuth();
			DateTime expires = new DateTime.fromMillisecondsSinceEpoch(auth['expires'] * 1000);
			if (expires.compareTo(new DateTime.now()) > 0) {
				loggedIn = true;
				username = window.localStorage['username'];
				new Timer(new Duration(seconds:1), () => relogin());
			} else {
				//it has expired already
				window.localStorage.remove('username');
			}
		}
	}

	togglePassword() {
		forgotPassword = !forgotPassword;
		resetStageTwo = false;
	}

	relogin() async {
		try {
			String token = window.localStorage['authToken'];
			String email = window.localStorage['authEmail'];

			await firebase.authWithCustomToken(token);

			HttpRequest request = await HttpRequest.request(server + "/auth/getSession", method: "POST",
			                                                requestHeaders: {"content-type": "application/json"},
			                                                sendData: JSON.encode({'email':email}));
			fireLoginSuccess(JSON.decode(request.response));
			print('relogin() success');
		}
		catch (err) {
			print('error relogin(): $err');

			//maybe the auth token has expired, present the prompt again
			loggedIn = false;
			window.localStorage.remove('username');
		}
	}

	bool _enterKey(event) {
		//detect enter key
		if (event is KeyboardEvent) {
			int code = (event as KeyboardEvent).keyCode;
			if (code != 13)
				return false;
		}

		return true;
	}

	oauthLogin(event, detail, Element target) async {
		String provider = target.attributes['provider'];
		String scope = 'email';
		if (provider == 'github')
			scope = 'user:email';

		waiting = true;
		try {
			Map response = await firebase.authWithOAuthPopup(provider, scope:scope);
			//print('user logged in with $provider: $response');

			String email = response[provider]['email'];
			Map sessionMap = await getSession(email);
			fireLoginSuccess(sessionMap);
		} catch (err) {
			print('failed login with $provider: $err');
		} finally {
			waiting = false;
		}
	}

	loginAttempt(event, detail, target) async {
		if (!_enterKey(event))
			return;

		if(passwordConfirmation) {
			verifyEmail(event,detail,target);
			return;
		}

		waiting = true;

		Map<String, String> credentials = {'email':email, 'password':password};

		try {
			await firebase.authWithPassword(credentials);
			Map sessionMap = await getSession(email);

			fireLoginSuccess(sessionMap);
			print('success');
		} catch (err) {
			try {
				//check to see if they have already verified their email (game window was closed when they clicked the link)
				HttpRequest request = await HttpRequest.request(server + "/auth/isEmailVerified", method: "POST",
				                                                requestHeaders: {"content-type": "application/json"},
				                                                sendData: JSON.encode({'email':email}));
				Map map = JSON.decode(request.response);
				if (map['result'] == 'success') {
					await _createNewUser(map);
				} else {
					throw(err);
				}
			} catch(err) {
				//we've never seen them before or they haven't yet verified their email
				Element warning = shadowRoot.querySelector('#warning');
				String error = err.toString();
				if (error.contains('Error: '))
					error = error.replaceFirst('Error: ', '');
				warning.text = error;
				print(err);
			}
		} finally {
			waiting = false;
		}
	}

	fireLoginSuccess(var payload) async {
		Timer acknowledgeTimer;
		new Service(['loginAcknowledged'], (m) {
			print('canceling success repeater');
			acknowledgeTimer.cancel();
		});
		acknowledgeTimer = new Timer.periodic(new Duration(seconds: 1), (Timer t) {
			dispatchEvent(new CustomEvent('loginSuccess', detail: payload));
		});
		dispatchEvent(new CustomEvent('loginSuccess', detail: payload));
	}

	Future<Map> getSession(String email) async {
		HttpRequest request = await HttpRequest.request(server + "/auth/getSession", method: "POST",
		                                                requestHeaders: {"content-type": "application/json"},
		                                                sendData: JSON.encode({'email':email}));
		window.localStorage['authToken'] = firebase.getAuth()['token'];
		window.localStorage['authEmail'] = email;
		Map sessionMap = JSON.decode(request.response);
		if (sessionMap['playerName'] != '') {
			window.localStorage['username'] = sessionMap['playerName'];
		}

		return sessionMap;
	}

	usernameSubmit(event, detail, target) async {
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
			dispatchEvent(new CustomEvent('setUsername', detail: newUsername));
		}
	}

	void signup(event, detail, target) {
		newSignup = true;
	}

	verifyEmail(event, detail, target) async {
		Element warning = shadowRoot.querySelector('#warning');
		warning.text = '';

		// not an email
		if (!email.contains('@')) {
			warning.text = 'Invalid email';
			return;
		}

		// password too short
		if (password.length < 6) {
			warning.text = 'Password too short';
			return;
		}

		// display password confirmation
		if (!passwordConfirmation) {
			passwordConfirmation = true;
			return;
		}

		// passwords don't match
		InputElement confirmPassword = shadowRoot.querySelector('#confirm-password');
		if (password != confirmPassword.value) {
			warning.text = "Passwords don't match";
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


		//Timer tooLongTimer = new Timer(new Duration(seconds: 5), () => timedout = true);

		HttpRequest request = await HttpRequest.request(server + "/auth/verifyEmail", method: "POST",
		                                                requestHeaders: {"content-type": "application/json"},
		                                                sendData: JSON.encode({'email':email}));
		//tooLongTimer.cancel();

		Map result = JSON.decode(request.response);
		if (result['result'] != 'OK') {
			waiting = false;
			print(result);
			return;
		}

		WebSocket ws = new WebSocket(websocket + "/awaitVerify");
		ws.onOpen.first.then((_) {
			Map map = {'email':email};
			ws.send(JSON.encode(map));
		});
		ws.onMessage.first.then((MessageEvent event) async {
			Map map = JSON.decode(event.data);
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
			await firebase.createUser({'email':email, 'password':password});

			newPassword = password;
			if (map['serverdata']['playerName'].trim() != '') {
				username = map['serverdata']['playerName'].trim();
				window.localStorage['username'] = username;
				//email already exists, make them choose a password
				existingUser = true;
			} else {
				newUser = true;
				newUsername = username;
				Map<String, String> credentials = {'email':email, 'password':password};
				window.localStorage['authToken'] = (await firebase.authWithPassword(credentials))['token'];
				window.localStorage['authEmail'] = map['serverdata']['playerEmail'];
				serverdata = map['serverdata'];
				print('new user');
			}
			fireLoginSuccess(map['serverdata']);
		} catch (err) {
			print("couldn't create user on firebase: $err");
		}
	}

	resetPassword() {
		if (!resetStageTwo) {
			firebase.resetPassword({'email': email});
			resetStageTwo = true;
			return;
		} else {
			InputElement newPasswordElement = shadowRoot.querySelector('#new-password-1');
			InputElement confirmationElement = shadowRoot.querySelector('#new-password-2');

			Element warning = shadowRoot.querySelector('#password-warning');

			if (newPasswordElement.value != confirmationElement.value) {
				warning.text = "Passwords don't match";
				return;
			}

			String tempPass = (shadowRoot.querySelector('#temp-password') as InputElement).value;
			String newPass = newPasswordElement.value;

			firebase.changePassword({
				                        'email': email,
				                        'oldPassword': tempPass,
				                        'newPassword': newPass
			                        }).catchError(print);
			togglePassword();
		}
	}
}