import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  var messages = [];
  String? attachedImageBase64;
  bool isLoading = false;
  TextEditingController messageController = TextEditingController();
  ScrollController scrollController = ScrollController();

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void showFullImage(String imageProvider, {bool isBase64 = false}) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Container(
          color: Colors.black,
          child: PhotoView(
            imageProvider: isBase64
                ? MemoryImage(base64Decode(imageProvider))
                : NetworkImage(imageProvider) as ImageProvider,
          ),
        ),
      ),
    );
  }

  Future<void> generateAndDescribeImage(String question, Map<String, String> headers) async {
    try {
      final resp = await http.post(
        Uri.parse("https://api.openai.com/v1/images/generations"),
        headers: headers,
        body: jsonEncode({
          "prompt": question,
          "n": 1,
          "size": "512x512",
          "response_format": "b64_json"
        }),
      );

      final imageBase64 = jsonDecode(resp.body)['data'][0]['b64_json'];

      setState(() {
        messages.add({
          "role": "assistant",
          "content": "Here is the image you requested:",
          "image": imageBase64
        });
      });

      // Now request GPT to describe the image
      final descResp = await http.post(
        Uri.parse("https://api.openai.com/v1/chat/completions"),
        headers: headers,
        body: jsonEncode({
          "model": "gpt-4o",
          "messages": [
            {
              "role": "user",
              "content": [
                {"type": "text", "text": "Describe this image"},
                {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,$imageBase64"}}
              ]
            }
          ]
        }),
      );

      final decoded = jsonDecode(descResp.body);
      final answer = decoded['choices'][0]['message']['content'];

      setState(() {
        messages.add({"role": "assistant", "content": answer});
      });
    } catch (e) {
      setState(() {
        messages.add({"role": "assistant", "content": "❌ Error generating image or description."});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("my_chatbot", style: TextStyle(color: Theme.of(context).indicatorColor)),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushNamed(context, '/');
            },
            icon: Icon(Icons.logout),
            color: Theme.of(context).indicatorColor,
          )
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              final isUser = msg['role'] == 'user';
              final hasImage = msg.containsKey('image');

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (!isUser)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: CircleAvatar(child: Text("🤖")),
                    ),
                  Flexible(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.lightGreen : Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasImage)
                            GestureDetector(
                              onTap: () => showFullImage(msg['image'], isBase64: true),
                              child: Image.memory(
                                base64Decode(msg['image']),
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          SizedBox(height: 8),
                          Text(msg['content'] ?? "", style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  if (isUser)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: CircleAvatar(child: Text("👤")),
                    ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(children: [
            Expanded(
              child: TextFormField(
                controller: messageController,
                decoration: InputDecoration(
                  hintText: "Ask anything",
                  suffixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      width: 1,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send),
              onPressed: () async {
                final question = messageController.text.trim();
                final lower = question.toLowerCase();

                if (question.isEmpty) return;

                final openAiKey = dotenv.env['OPENAI_API_KEY'];
                final headers = {
                  "Content-Type": "application/json",
                  "Authorization": "Bearer $openAiKey"
                };

                setState(() {
                  isLoading = true;
                  messages.add({"role": "user", "content": question});
                });

                final isImagePrompt = lower.startsWith("generate") ||
                    lower.startsWith("create") ||
                    lower.contains("generate an image") ||
                    lower.contains("create an image");

                if (isImagePrompt) {
                  await generateAndDescribeImage(question, headers);
                } else {
                  try {
                    final resp = await http.post(
                      Uri.parse("https://api.openai.com/v1/chat/completions"),
                      headers: headers,
                      body: jsonEncode({
                        "model": "gpt-4o",
                        "messages": messages.map((msg) => {
                          "role": msg['role'],
                          "content": msg['content']
                        }).toList()
                      }),
                    );
                    final decoded = jsonDecode(resp.body);
                    final answer = decoded['choices'][0]['message']['content'];

                    setState(() {
                      messages.add({"role": "assistant", "content": answer});
                    });
                  } catch (e) {
                    setState(() {
                      messages.add({"role": "assistant", "content": "❌ Error from OpenAI API."});
                    });
                  }
                }

                messageController.clear();
                setState(() => isLoading = false);
                scrollToBottom();
              },
            )
          ]),
        )
      ]),
    );
  }
}
