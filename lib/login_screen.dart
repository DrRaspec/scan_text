import 'package:flutter/material.dart';
import 'package:scan_text/scan_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool isPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                const SizedBox(height: 32.0),

                TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    labelText: 'Enter your name',
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.document_scanner_outlined),
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ScanScreen(),
                          ),
                        );

                        if (result != null && result is String) {
                          _textController.text = result;
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 16.0),

                TextField(
                  controller: _passwordController,
                  obscureText: !isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Enter your password',
                    border: OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: .min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ScanScreen(),
                              ),
                            );

                            if (result != null && result is String) {
                              _passwordController.text = result;
                            }
                          },

                          child: const Icon(Icons.document_scanner_outlined),
                        ),

                        const SizedBox(width: 16),

                        GestureDetector(
                          onTap: () {
                            setState(() {
                              isPasswordVisible = !isPasswordVisible;
                            });
                          },

                          child: const Icon(Icons.visibility),
                        ),
                        const SizedBox(width: 16),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 64),

                ElevatedButton(
                  onPressed: () {
                    String name = _textController.text;
                    String password = _passwordController.text;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Name: $name, Password: $password'),
                      ),
                    );
                  },
                  child: const Text('Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
