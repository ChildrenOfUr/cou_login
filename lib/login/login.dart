library login;

import 'dart:html';
import 'package:polymer/polymer.dart';
import 'package:firebase/firebase.dart';
import 'dart:async';
import 'dart:convert';

@CustomTag('ur-login')
class UrLogin extends PolymerElement {
	@published String serveraddress, serverwebsocket;
	@published bool  newUser = false;
	@observable bool timedout = false, newSignup = false, waiting = false, invalidEmail = false;
	@observable bool waitingOnEmail = false, existingUser = false, loggedIn = false, passwordTooShort = false;
	@observable String username, email, password, newUsername = '', newPassword = '';
	Firebase firebase;
	Map serverdata;

	UrLogin.created() : super.created() {
		firebase = new Firebase("https://blinding-fire-920.firebaseio.com");
		if(window.localStorage.containsKey('username')) {
			loggedIn = true;
			username = window.localStorage['username'];
			new Timer(new Duration(seconds:1), () => relogin());
		}
	}

	relogin() async {
		try {
			String token = window.localStorage['authToken'];
			String email = window.localStorage['authEmail'];
			await firebase.authWithCustomToken(token);

			HttpRequest request = await HttpRequest.request(serveraddress + "/auth/getSession", method: "POST",
			                                                requestHeaders: {"content-type": "application/json"},
			                                                sendData: JSON.encode({'email':email}));
			dispatchEvent(new CustomEvent('loginSuccess', detail: JSON.decode(request.response)));
			print('relogin() success');
		}
		catch(err) {
			print('error relogin(): $err');

			//maybe the auth token has expired, present the prompt again
			loggedIn = false;
			window.localStorage.remove('username');
		}
	}

	bool _enterKey(event) {
		//detect enter key
		if(event is KeyboardEvent) {
			int code = (event as KeyboardEvent).keyCode;
			if(code != 13)
				return false;
		}

		return true;
	}

	oauthLogin(event, detail, Element target) async
	{
		String provider = target.attributes['provider'];
		String scope = 'email';
		if(provider == 'github')
			scope = 'user:email';

		waiting = true;
		try {
			Map response = await firebase.authWithOAuthPopup(provider, scope:scope);
			//print('user logged in with $provider: $response');

			String email = response[provider]['email'];
			Map sessionMap = await getSession(email);
			dispatchEvent(new CustomEvent('loginSuccess', detail: sessionMap));
		}
		catch(err) {
			print('failed login with $provider: $err');
		}
		finally {
			waiting = false;
		}
	}

	loginAttempt(event, detail, target) async {
		if(!_enterKey(event))
			return;

		waiting = true;
		Map<String, String> credentials = {'email':email, 'password':password};

		try {
			await firebase.authWithPassword(credentials);
			Map sessionMap = await getSession(email);
			dispatchEvent(new CustomEvent('loginSuccess', detail: sessionMap));
			print('success');
		}
		catch(err) {
			print(err);
		}
		finally
		{
			waiting = false;
		}
	}

	Future<Map> getSession(String email) async
	{
		HttpRequest request = await HttpRequest.request(serveraddress + "/auth/getSession", method: "POST",
		                                                requestHeaders: {"content-type": "application/json"},
		                                                sendData: JSON.encode({'email':email}));
		window.localStorage['authToken'] = firebase.getAuth()['token'];
		window.localStorage['authEmail'] = email;
		Map sessionMap = JSON.decode(request.response);
		if(sessionMap['playerName'] != '')
			window.localStorage['username'] = sessionMap['playerName'];

		return sessionMap;
	}

	usernameSubmit(event, detail, target) async
	{
		if(!_enterKey(event))
			return;

		if(newUsername == '' || newPassword == '')
			return;

		if(existingUser) {
			dispatchEvent(new CustomEvent('loginSuccess', detail: serverdata));
		}
		else {
			dispatchEvent(new CustomEvent('setUsername', detail: newUsername));
		}
	}

	void signup(event, detail, target) {
		newSignup = true;
	}

	verifyEmail(event, detail, target) async
	{
		if(!email.contains('@')) {
			invalidEmail = true;
			return;
		}
		else {
			invalidEmail = false;
		}
		if(password.length < 6) {
			passwordTooShort = true;
			return;
		}
		else {
			passwordTooShort = false;
		}

		if(!_enterKey(event))
			return;

		if(email == '')
			return;

		waiting = true;
		waitingOnEmail = true;

		Timer tooLongTimer = new Timer(new Duration(seconds: 5), () => timedout = true);

		HttpRequest request = await HttpRequest.request(serveraddress + "/auth/verifyEmail", method: "POST",
		                                                requestHeaders: {"content-type": "application/json"},
		                                                sendData: JSON.encode({'email':email}));

		tooLongTimer.cancel();

		Map result = JSON.decode(request.response);
		if(result['result'] != 'OK') {
			waiting = false;
			print(result);
			return;
		}

		WebSocket ws = new WebSocket(serverwebsocket + "/awaitVerify");
		ws.onOpen.first.then((_) {
			Map map = {'email':email};
			ws.send(JSON.encode(map));
		});
		ws.onMessage.first.then((MessageEvent event) async {
			Map map = JSON.decode(event.data);
			if(map['result'] == 'success') {
				try {
					//create the user in firebase
					await firebase.createUser({'email':email, 'password':password});

					newPassword = password;
					if(map['serverdata']['playerName'].trim() != '') {
						username = map['serverdata']['playerName'].trim();
						window.localStorage['username'] = username;
						//email already exists, make them choose a password
						existingUser = true;
					}
					else {
						newUser = true;
						newUsername = username;
						serverdata = map['serverdata'];
						print('new user');
					}
					dispatchEvent(new CustomEvent('loginSuccess', detail: map['serverdata']));
				}
				catch(err) {
					print("couldn't create user on firebase: $err");
				}
			}
			else {
				print('problem verifying email address: ${map['result']}');

			}

			waiting = false;
		});
	}
}