import 'dart:async';

import 'package:flutter/material.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _slides = [
    (
      'A calmer way to run your pharmacy',
      'Keep your shop, stock, and daily work together.',
      'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?auto=format&fit=crop&w=1600&q=85',
    ),
    (
      'Know what needs attention',
      'Keep essential shop information close at hand.',
      'https://images.unsplash.com/photo-1584982751601-97dcc096659c?auto=format&fit=crop&w=1600&q=85',
    ),
    (
      'Make every day more manageable',
      'A clear workspace for owners and pharmacy teams.',
      'https://images.unsplash.com/photo-1471864190281-a93a3070b6de?auto=format&fit=crop&w=1600&q=85',
    ),
  ];

  final _pageController = PageController();
  Timer? _slideTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _slideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_pageController.hasClients) return;
      final next = (_currentPage + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final imageHeight = constraints.maxHeight < 650
                ? 220.0
                : (constraints.maxHeight * 0.42).clamp(260.0, 380.0).toDouble();
            return Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 960,
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B4F3A),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.local_pharmacy_rounded,
                                color: Colors.white,
                                size: 27,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'MediManage',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF173B3A),
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: imageHeight,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: _slides.length,
                            onPageChanged: (index) =>
                                setState(() => _currentPage = index),
                            itemBuilder: (context, index) {
                              final slide = _slides[index];
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      slide.$3,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                                color: const Color(0xFFDCEBE8),
                                                child: const Icon(
                                                  Icons.local_pharmacy_outlined,
                                                  size: 72,
                                                  color: Color(0xFF0B4F3A),
                                                ),
                                              ),
                                    ),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withValues(
                                              alpha: 0.68,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 20,
                                      right: 20,
                                      bottom: 20,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            slide.$1,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            slide.$2,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Previous slide',
                              onPressed: _currentPage == 0
                                  ? null
                                  : () => _pageController.previousPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                    ),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            ...List.generate(
                              _slides.length,
                              (index) => SizedBox(
                                width: 40,
                                height: 44,
                                child: Semantics(
                                  label:
                                      'Slide ${index + 1} of ${_slides.length}',
                                  button: true,
                                  child: InkWell(
                                    onTap: () => _pageController.animateToPage(
                                      index,
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _currentPage == index
                                              ? const Color(0xFF0B4F3A)
                                              : const Color(0xFFB6C7C4),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Next slide',
                              onPressed: _currentPage == _slides.length - 1
                                  ? null
                                  : () => _pageController.nextPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                    ),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Your pharmacy, in one place',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF173B3A),
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Manage your medical shop, sales, inventory, and business reports in one place.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/login'),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Get Started'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pushNamed('/terms'),
                              child: const Text('Terms of Use'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pushNamed('/privacy'),
                              child: const Text('Privacy Policy'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
