library login;

import 'dart:html';
import 'dart:math';
import 'package:polymer/polymer.dart';
import 'package:firebase/firebase.dart';
import 'dart:async';
import 'dart:convert';
import 'package:transmit/transmit.dart';

@CustomTag('ur-login')
class UrLogin extends PolymerElement {
	static final bool DEBUG_ENABLED = false;

	@published String base;
	@published String gameServer = 'http://server.childrenofur.com:8181';
	@published String server;
	@published String websocket;

	@observable bool existingUser = false;
	@observable bool forgotPassword = false;
	@observable bool invalidEmail = false;
	@observable bool loggedIn = false;
	@observable bool newSignup = false;
	@observable bool newUser = false;
	@observable bool passwordConfirmation = false;
	@observable bool passwordTooShort = false;
	@observable bool resetStageTwo = false;
	@observable bool serviceLoggedIn = false;
	@observable bool timedout = false;
	@observable bool waiting = false;
	@observable bool waitingOnEmail = false;

	@observable String avatarUrl = 'packages/cou_login/login/player_unknown.png';
	@observable String email = '';
	@observable String newPassword = '';
	@observable String newUsername = '';
	@observable String password = '';
	@observable String username = '';

	Firebase firebase;
	Map serverdata;

	// Displayed as: {greeting}, {username}
	static final List<String> GREETING_PREFIXES = [
		'Good to see you',
		'Greetings',
		'Hello',
		'Hello there',
		'Have fun',
		'Hi',
		'Hi there',
		'It\'s good to see you',
		'Nice of you to join us',
		'Thanks for joining us',
		'Welcome',
		'Welcome back'
	];
	String greetingPrefix = GREETING_PREFIXES.first;

	UrLogin.created() : super.created() {
		firebase = new Firebase('https://$base.firebaseio.com');
		if (window.localStorage.containsKey('username')) {
			// Let's see if our firebase auth is current
			Map auth = firebase.getAuth();
			DateTime expires = new DateTime.now();

			if (auth != null) {
				expires = new DateTime.fromMillisecondsSinceEpoch(auth['expires'] * 1000);
			}

			username = window.localStorage['username'] ?? '';

			if (expires.compareTo(new DateTime.now()) > 0) {
				greetingPrefix = GREETING_PREFIXES[new Random().nextInt(GREETING_PREFIXES.length)];
				loggedIn = true;
				new Timer(new Duration(seconds:1), () => relogin());
			} else {
				// It has expired already
				window.localStorage.remove('username');
			}
		}
	}

	void debug(dynamic object) {
		if (DEBUG_ENABLED) {
			print(object);
		}
	}

	void togglePassword() {
		forgotPassword = !forgotPassword;
		resetStageTwo = false;
	}

	Future relogin() async {
		try {
			String token = window.localStorage['authToken'];
			String email = window.localStorage['authEmail'];

			await firebase.authWithCustomToken(token);

			HttpRequest request = await HttpRequest.request(
				server + '/auth/getSession', method: 'POST',
				requestHeaders: {'content-type': 'application/json'},
			    sendData: JSON.encode({'email':email}));
			fireLoginSuccess(JSON.decode(request.response));
			debug('relogin() success');
		} catch (err) {
			debug('error relogin(): $err');

			// Maybe the auth token has expired, present the prompt again
			loggedIn = false;
			window.localStorage.remove('username');
		}
	}

	bool _enterKey(event) {
		// Detect enter key
		if (event is KeyboardEvent) {
			int code = (event as KeyboardEvent).keyCode;

			if (code != 13) {
				return false;
			}
		}

		return true;
	}

	Future oauthLogin(event, detail, Element target) async {
		String provider = target.attributes['provider'];
		String scope = 'email';

		if (provider == 'github') {
			scope = 'user:email';
		}

		waiting = true;

		try {
			Map response = await firebase.authWithOAuthPopup(provider, scope:scope);
			debug('user logged in with $provider: $response');

			String email = response[provider]['email'];
			Map sessionMap = await getSession(email);
			fireLoginSuccess(sessionMap);
		} catch (err) {
			debug('failed login with $provider: $err');
		} finally {
			waiting = false;
			serviceLoggedIn = true;
		}
	}

	Future loginAttempt(event, detail, target) async {
		if (!_enterKey(event))
			return;

		if (passwordConfirmation) {
			verifyEmail(event,detail,target);
			return;
		}

		waiting = true;

		Map<String, String> credentials = {'email':email, 'password':password};

		try {
			await firebase.authWithPassword(credentials);
			Map sessionMap = await getSession(email);

			fireLoginSuccess(sessionMap);
			debug('success');
		} catch (err) {
			try {
				// Check to see if they have already verified their email (game window was closed when they clicked the link)
				HttpRequest request = await HttpRequest.request(
					server + '/auth/isEmailVerified',
					method: 'POST',
				    requestHeaders: {'content-type': 'application/json'},
				    sendData: JSON.encode({'email':email}));
				Map map = JSON.decode(request.response);
				if (map['result'] == 'success') {
					await _createNewUser(map);
				} else {
					throw(err);
				}
			} catch (err) {
				// We've never seen them before or they haven't yet verified their email
				Element warning = shadowRoot.querySelector('#warning');
				String error = err.toString();
				if (error.contains('Error: '))
					error = error.replaceFirst('Error: ', '');
				warning.text = error;
				debug(err);
			}
		} finally {
			waiting = false;
		}
	}

	Future fireLoginSuccess(var payload) async {
		Timer acknowledgeTimer;
		new Service(['loginAcknowledged'], (m) {
			debug('canceling success repeater');
			acknowledgeTimer.cancel();
		});
		acknowledgeTimer = new Timer.periodic(new Duration(seconds: 1), (Timer t) {
			dispatchEvent(new CustomEvent('loginSuccess', detail: payload));
		});
		dispatchEvent(new CustomEvent('loginSuccess', detail: payload));
	}

	Future<Map> getSession(String email) async {
		HttpRequest request = await HttpRequest.request(
			server + '/auth/getSession',
			method: 'POST',
		    requestHeaders: {'content-type': 'application/json'},
		    sendData: JSON.encode({'email':email}));

		window.localStorage['authToken'] = firebase.getAuth()['token'];
		window.localStorage['authEmail'] = email;

		Map sessionMap = JSON.decode(request.response);
		if (sessionMap['playerName'] != '') {
			window.localStorage['username'] = sessionMap['playerName'];
		}

		return sessionMap;
	}

	Future usernameSubmit(event, detail, target) async {
		if (!_enterKey(event)) {
			return;
		}

		// Remove leading/trailing spaces
		newUsername = newUsername.trim();

		// Username too short
		if (newUsername.length < 3) {
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

	void updateAvatarPreview(event, detail, target) {
		// Read input
		String getUsername = newUsername;

		// Provide a default
		if (getUsername == '') {
			getUsername = 'Hectaku';
		}

		// $server = http|//hostname|8383 (| = split point)
		//           ^  +     ^    (-  ^)
		HttpRequest.getString('$gameServer/getSpritesheets?username=$getUsername').then((String json) {
			avatarUrl = JSON.decode(json)['base'];

			// Used for sizing
			ImageElement avatarData = new ImageElement()
				..src = avatarUrl;

			// Resize elements to fit image
			avatarData.onLoad.listen((_) {
				shadowRoot.querySelector('#avatar-container').style
					..width = (avatarData.naturalWidth / 15).toString() + 'px';
				shadowRoot.querySelector('#avatar-img').style
					..width = (avatarData.naturalWidth).toString() + 'px'
					..height = (avatarData.naturalHeight).toString() + 'px';
			});
		});
	}

	Future verifyEmail(event, detail, target) async {
		Element warning = shadowRoot.querySelector('#warning');
		warning.text = '';

		// Not an email
		if (!email.contains('@')) {
			warning.text = 'Invalid email';
			return;
		}

		// Password too short
		if (password.length < 6) {
			warning.text = 'Password too short';
			return;
		}

		// Display password confirmation
		if (!passwordConfirmation) {
			passwordConfirmation = true;
			return;
		}

		// Passwords don't match
		InputElement confirmPassword = shadowRoot.querySelector('#confirm-password');
		if (password != confirmPassword.value) {
			warning.text = 'Passwords don\'t match';
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

		// Timer tooLongTimer = new Timer(new Duration(seconds: 5), () => timedout = true);

		HttpRequest request = await HttpRequest.request(
			server + '/auth/verifyEmail',
			method: 'POST',
		    requestHeaders: {'content-type': 'application/json'},
		    sendData: JSON.encode({'email':email}));
		// tooLongTimer.cancel();

		Map result = JSON.decode(request.response);
		if (result['result'] != 'OK') {
			waiting = false;
			debug(result);
			return;
		}

		WebSocket ws = new WebSocket(websocket + '/awaitVerify');

		ws.onOpen.first.then((_) {
			Map map = {'email':email};
			ws.send(JSON.encode(map));
		});

		ws.onMessage.first.then((MessageEvent event) async {
			Map map = JSON.decode(event.data);
			if (map['result'] == 'success') {
				await _createNewUser(map);
			} else {
				debug('problem verifying email address: ${map['result']}');

			}

			waiting = false;
		});
	}

	Future _createNewUser(Map map) async {
		try {
			// Create the user in firebase
			await firebase.createUser({'email':email, 'password':password});

			newPassword = password;
			if (map['serverdata']['playerName'].trim() != '') {
				username = map['serverdata']['playerName'].trim();
				window.localStorage['username'] = username;

				// Email already exists, make them choose a password
				existingUser = true;
			} else {
				newUser = true;
				newUsername = username;
				Map<String, String> credentials = {'email':email, 'password':password};
				window.localStorage['authToken'] = (await firebase.authWithPassword(credentials))['token'];
				window.localStorage['authEmail'] = map['serverdata']['playerEmail'];
				serverdata = map['serverdata'];
				debug('new user');
			}
			fireLoginSuccess(map['serverdata']);
		} catch (err) {
			debug('couldn\'t create user on firebase: $err');
		}
	}

	void resetPassword() {
		if (!resetStageTwo) {
			firebase.resetPassword({'email': email});
			resetStageTwo = true;
			return;
		} else {
			InputElement newPasswordElement = shadowRoot.querySelector('#new-password-1');
			InputElement confirmationElement = shadowRoot.querySelector('#new-password-2');

			Element warning = shadowRoot.querySelector('#password-warning');

			if (newPasswordElement.value != confirmationElement.value) {
				warning.text = 'Passwords don\'t match';
				return;
			}

			String tempPass = (shadowRoot.querySelector('#temp-password') as InputElement).value;
			String newPass = newPasswordElement.value;

			firebase.changePassword({
				'email': email,
				'oldPassword': tempPass,
				'newPassword': newPass
			}).catchError(debug);

			togglePassword();
		}
	}
}
