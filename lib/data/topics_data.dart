import 'dart:math';
import 'package:flutter/material.dart';

class TopicCategory {
  const TopicCategory({required this.name, required this.icon, required this.prompts});
  final String name;
  final IconData icon;
  final List<String> prompts;
}

final List<TopicCategory> kTopicCategories = [
  TopicCategory(
    name: 'Daily Life',
    icon: Icons.wb_sunny_outlined,
    prompts: [
      'What does a typical day look like for you?',
      "What's your favorite way to relax after a long day?",
      'Do you prefer mornings or evenings? Why?',
      "What's one habit you'd like to build this year?",
      'How do you usually spend your weekends?',
      "What's a small thing that made you happy recently?",
      "Do you cook for yourself often? What's your go-to meal?",
      'What does your ideal day off look like?',
    ],
  ),
  TopicCategory(
    name: 'Travel',
    icon: Icons.flight_takeoff_rounded,
    prompts: [
      "What's the most interesting place you've ever visited?",
      'Would you rather travel alone or with friends? Why?',
      "What's a country you'd love to visit and why?",
      'Do you prefer beaches, mountains, or cities when you travel?',
      "What's the best meal you've had while traveling?",
      'Have you ever gotten lost in a new city? What happened?',
      "What's one thing you always pack when you travel?",
      'If you could live in another country for a year, where would you go?',
    ],
  ),
  TopicCategory(
    name: 'Work & Study',
    icon: Icons.work_outline_rounded,
    prompts: [
      'What do you do for work or study right now?',
      "What's the most challenging part of your job or studies?",
      'Do you prefer working alone or in a team?',
      'What skill are you currently trying to improve?',
      'What does a perfect workday look like for you?',
      'Have you ever changed careers or fields of study? Why?',
      "What's one piece of advice you'd give someone starting in your field?",
      'Do you think remote work is better than working in an office?',
    ],
  ),
  TopicCategory(
    name: 'Technology',
    icon: Icons.smartphone_rounded,
    prompts: [
      'How many hours a day do you spend on your phone?',
      'What app could you not live without?',
      'Do you think AI will change your job in the next few years?',
      "What's a piece of technology that made your life easier?",
      'Do you prefer reading physical books or e-books?',
      "What's your opinion on social media — good or bad for society?",
      'Have you ever tried a new gadget that disappointed you?',
      'What technology do you think will be common in 10 years?',
    ],
  ),
  TopicCategory(
    name: 'Opinions & Hypotheticals',
    icon: Icons.lightbulb_outline_rounded,
    prompts: [
      'If you could have any superpower, what would it be and why?',
      "What's something you believe that most people disagree with?",
      'If you won a large sum of money, what would you do first?',
      "What's one law you'd change if you could?",
      'Do you think success is more about talent or hard work?',
      'If you could meet anyone, living or dead, who would it be?',
      "What's a skill you wish was taught in school?",
      'Would you rather be famous or wealthy? Why?',
    ],
  ),
  TopicCategory(
    name: 'IELTS Speaking Part 1',
    icon: Icons.looks_one_outlined,
    prompts: [
      "Let's talk about your hometown. What do you like about it?",
      'Do you work or are you a student?',
      'What kind of music do you enjoy listening to?',
      'How do you usually spend your free time?',
      'Do you prefer spending time indoors or outdoors?',
      "What's your favorite season of the year?",
      'Do you often cook at home?',
      "What's something you're looking forward to this year?",
    ],
  ),
  TopicCategory(
    name: 'IELTS Speaking Part 2',
    icon: Icons.looks_two_outlined,
    prompts: [
      'Describe a person who has influenced you. You should say: who this person is, how you know them, what they are like, and explain why they influenced you.',
      'Describe a place you would like to visit. You should say: where it is, how you know about it, what you would do there, and explain why you want to go.',
      'Describe a skill you would like to learn. You should say: what it is, why you want to learn it, how you would learn it, and explain how it would help you.',
      'Describe a memorable trip you have taken. You should say: where you went, who you went with, what you did there, and explain why it was memorable.',
      'Describe a book or film that made a strong impression on you. You should say: what it was, what it was about, when you experienced it, and explain why it impressed you.',
      'Describe a time you helped someone. You should say: who you helped, what the situation was, what you did, and explain how it made you feel.',
    ],
  ),
  TopicCategory(
    name: 'IELTS Speaking Part 3',
    icon: Icons.looks_3_outlined,
    prompts: [
      'Do you think technology makes people more or less connected to each other?',
      'How has the way people communicate changed in the last 20 years?',
      "Do you think it's important for schools to teach practical life skills?",
      'What are the advantages and disadvantages of living in a big city?',
      'How do you think work will change in the future?',
      'Is it better to specialize in one skill or have knowledge in many areas?',
      'Do you think traditional customs are becoming less important in modern society?',
      'What role should government play in protecting the environment?',
    ],
  ),
];

class TopicsRepository {
  TopicsRepository._();
  static final Random _random = Random();

  /// A random prompt, optionally scoped to one category. With no
  /// category given, it pulls from every category — used for the
  /// shuffle-able suggestion on the call screen.
  static String randomPrompt({String? categoryName}) {
    final pool = categoryName == null
        ? kTopicCategories.expand((c) => c.prompts).toList()
        : kTopicCategories.firstWhere((c) => c.name == categoryName).prompts;
    return pool[_random.nextInt(pool.length)];
  }
}
