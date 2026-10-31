// Moment templates — the catalogue.
//
// 25 ready-to-post designs in five groups: Portraits, Collages, Creator,
// Trending (formats people are posting right now) and Quotes & advice.
// Coordinates are in the 360 × 640 design space (centre x, centre y; sizes
// in the same units). Every text is editable and every photo frame is
// fillable; decorations hold the layout.

import 'package:flutter/painting.dart';

import 'template_model.dart';

const _white = Color(0xFFFFFFFF);
const _ink = Color(0xFF111925);
const _cream = Color(0xFFF6EFE6);
const _violet = Color(0xFF8D78FF);
const _pink = Color(0xFFE795D7);
const _peach = Color(0xFFFFB58F);
const _blue = Color(0xFF72A7FF);
const _mint = Color(0xFF68D7CD);
const _yellow = Color(0xFFF6D365);
const _red = Color(0xFFF5636B);

TBackdrop _bd(BackdropStyle s, int palette, {double grain = .25, bool animate = true}) =>
    TBackdrop(s, [...backdropPalettes[palette]], grain: grain, animate: animate);

/// Short alias for an offset in design units.
Offset _o(double x, double y) => Offset(x, y);

/// Every template, in gallery order.
final momentTemplates = <MomentTemplate>[
  // ---------------------------------------------------------------- Portraits
  MomentTemplate(
    id: 'editorial',
    name: 'Editorial',
    category: TemplateCategory.portrait,
    backdrop: () => _bd(BackdropStyle.paper, 2, grain: .35, animate: false),
    build: () => [
      TElement.slot(_o(180, 330), const Size(300, 420), hint: 'Portrait', look: 'moon'),
      TElement.text('THE EDIT', _o(180, 70), font: 'Playfair Display', fontSize: 44, color: _ink, weight: FontWeight.w800, spacing: 6),
      TElement.deco(DecoKind.line, _o(180, 102), const Size(300, 1.2), color: _ink),
      TElement.text('Issue 07 · Autumn', _o(180, 116), font: 'Cormorant Garamond', fontSize: 14, color: _ink, weight: FontWeight.w600, italic: true),
      TElement.text('Your Name', _o(180, 575), font: 'DM Serif Display', fontSize: 30, color: _ink, weight: FontWeight.w400),
      TElement.text('photographed by @you', _o(180, 606), fontSize: 11, color: _ink, weight: FontWeight.w600, spacing: 2, upper: true, role: TextRole.mention),
    ],
  ),
  MomentTemplate(
    id: 'polaroid',
    name: 'Polaroid',
    category: TemplateCategory.portrait,
    backdrop: () => _bd(BackdropStyle.paper, 2, grain: .4, animate: false),
    build: () => [
      TElement.deco(DecoKind.tape, _o(150, 128), const Size(90, 26), color: const Color(0xCCE795D7), rotation: -.35),
      TElement.slot(_o(180, 300), const Size(270, 330), shape: SlotShape.polaroid, rotation: -.05, hint: 'Your photo'),
      TElement.deco(DecoKind.tape, _o(268, 140), const Size(80, 24), color: const Color(0xCC72A7FF), rotation: .5),
      TElement.text('summer, unfiltered', _o(180, 445), font: 'Caveat', fontSize: 30, color: _ink, weight: FontWeight.w600, rotation: -.05),
      TElement.text('📍 somewhere good', _o(180, 560), fontSize: 13, color: _ink, bg: TextBg.sticker, bgColor: _white, role: TextRole.location),
    ],
  ),
  MomentTemplate(
    id: 'cover',
    name: 'Magazine cover',
    category: TemplateCategory.portrait,
    backdrop: () => _bd(BackdropStyle.linear, 4, animate: false),
    build: () => [
      TElement.slot(_o(180, 320), templateSize, hint: 'Cover photo'),
      TElement.deco(DecoKind.rect, _o(180, 70), const Size(360, 140), color: const Color(0x99000000), color2: const Color(0x00000000)),
      TElement.text('PHLIO', _o(180, 66), font: 'Playfair Display', fontSize: 88, color: _white, weight: FontWeight.w900, spacing: 2),
      TElement.text('THE NEW\nFACES\nOF 2026', _o(92, 400), width: 170, font: 'Bebas Neue', fontSize: 40, color: _white, weight: FontWeight.w400, align: TextAlign.left, lineHeight: .95),
      TElement.text('Inside: the looks, the playlists, the people', _o(104, 490), width: 190, fontSize: 12, color: _yellow, align: TextAlign.left, weight: FontWeight.w800),
      TElement.text('NO. 12', _o(300, 600), fontSize: 13, color: _white, spacing: 3, weight: FontWeight.w800),
    ],
  ),
  MomentTemplate(
    id: 'arch',
    name: 'Soft glow',
    category: TemplateCategory.portrait,
    backdrop: () => _bd(BackdropStyle.aurora, 0, grain: .2),
    build: () => [
      TElement.slot(_o(180, 290), const Size(250, 360), shape: SlotShape.arch, border: _white, borderWidth: 2, shadow: true, hint: 'Portrait'),
      TElement.text('Golden hour', _o(180, 520), font: 'Pacifico', fontSize: 40, color: _white, weight: FontWeight.w400),
      TElement.text('feeling like myself again', _o(180, 568), font: 'Cormorant Garamond', fontSize: 18, color: _cream, italic: true, weight: FontWeight.w600),
    ],
  ),
  MomentTemplate(
    id: 'duotone',
    name: 'Mono bold',
    category: TemplateCategory.portrait,
    backdrop: () => _bd(BackdropStyle.halftone, 4, animate: false),
    build: () => [
      TElement.slot(_o(205, 320), const Size(310, 640), look: 'inkwell', hint: 'Portrait'),
      TElement.text('MAIN CHARACTER', _o(28, 320), width: 600, font: 'Anton', fontSize: 46, color: _yellow, weight: FontWeight.w400, spacing: 2, rotation: -1.5708),
      TElement.text('@yourname', _o(250, 600), fontSize: 14, color: _ink, bg: TextBg.pill, bgColor: _yellow, role: TextRole.mention),
    ],
  ),

  // ----------------------------------------------------------------- Collages
  MomentTemplate(
    id: 'grid4',
    name: 'Grid of four',
    category: TemplateCategory.collage,
    backdrop: () => _bd(BackdropStyle.linear, 2, animate: false, grain: .1),
    build: () => [
      TElement.text('the week in four', _o(180, 62), font: 'DM Serif Display', fontSize: 30, color: _ink, weight: FontWeight.w400),
      TElement.slot(_o(96, 222), const Size(160, 200), shape: SlotShape.rounded, radius: 14, hint: 'Mon'),
      TElement.slot(_o(264, 222), const Size(160, 200), shape: SlotShape.rounded, radius: 14, hint: 'Wed'),
      TElement.slot(_o(96, 434), const Size(160, 200), shape: SlotShape.rounded, radius: 14, hint: 'Fri'),
      TElement.slot(_o(264, 434), const Size(160, 200), shape: SlotShape.rounded, radius: 14, hint: 'Sun'),
      TElement.text('#weeklyrecap', _o(180, 585), fontSize: 14, color: _ink, weight: FontWeight.w800, role: TextRole.tag),
    ],
  ),
  MomentTemplate(
    id: 'filmstrip',
    name: 'Film strip',
    category: TemplateCategory.collage,
    backdrop: () => _bd(BackdropStyle.film, 3, grain: .45),
    build: () => [
      TElement.deco(DecoKind.sprockets, _o(180, 320), const Size(250, 560), color: const Color(0xFF151413)),
      TElement.slot(_o(180, 140), const Size(200, 160), hint: 'Frame 1'),
      TElement.slot(_o(180, 320), const Size(200, 160), hint: 'Frame 2'),
      TElement.slot(_o(180, 500), const Size(200, 160), hint: 'Frame 3'),
      TElement.text("31 OCT '26", _o(250, 590), font: 'Courier Prime', fontSize: 15, color: _peach, weight: FontWeight.w700, spacing: 1),
    ],
  ),
  MomentTemplate(
    id: 'scrapbook',
    name: 'Scrapbook',
    category: TemplateCategory.collage,
    backdrop: () => _bd(BackdropStyle.paper, 2, grain: .45, animate: false),
    build: () => [
      TElement.slot(_o(120, 170), const Size(170, 200), shape: SlotShape.polaroid, rotation: -.12),
      TElement.slot(_o(250, 300), const Size(170, 200), shape: SlotShape.polaroid, rotation: .1),
      TElement.slot(_o(130, 455), const Size(170, 200), shape: SlotShape.polaroid, rotation: -.06),
      TElement.deco(DecoKind.tape, _o(110, 75), const Size(70, 20), color: const Color(0xCCF6D365), rotation: -.3),
      TElement.deco(DecoKind.tape, _o(260, 200), const Size(70, 20), color: const Color(0xCC68D7CD), rotation: .4),
      TElement.text('little things\nlately', _o(275, 480), width: 140, font: 'Caveat', fontSize: 32, color: _ink, weight: FontWeight.w700, rotation: .08),
      TElement.text('♡', _o(300, 90), font: 'Caveat', fontSize: 48, color: _red),
    ],
  ),
  MomentTemplate(
    id: 'beforeafter',
    name: 'Before / after',
    category: TemplateCategory.collage,
    backdrop: () => _bd(BackdropStyle.linear, 4, animate: false),
    build: () => [
      TElement.slot(_o(180, 160), const Size(360, 318), hint: 'Before'),
      TElement.slot(_o(180, 481), const Size(360, 318), hint: 'After'),
      TElement.deco(DecoKind.line, _o(180, 320), const Size(360, 4), color: _white),
      TElement.text('BEFORE', _o(66, 290), fontSize: 13, color: _ink, bg: TextBg.pill, bgColor: _white, spacing: 2),
      TElement.text('AFTER', _o(62, 610), fontSize: 13, color: _white, bg: TextBg.pill, bgColor: _violet, spacing: 2),
    ],
  ),
  MomentTemplate(
    id: 'mosaic',
    name: 'Mosaic',
    category: TemplateCategory.collage,
    backdrop: () => _bd(BackdropStyle.mesh, 0),
    build: () => [
      TElement.slot(_o(180, 210), const Size(320, 300), shape: SlotShape.rounded, radius: 22, hint: 'Main photo'),
      TElement.slot(_o(98, 470), const Size(156, 190), shape: SlotShape.rounded, radius: 22),
      TElement.slot(_o(262, 470), const Size(156, 190), shape: SlotShape.rounded, radius: 22),
      TElement.text('weekend mode', _o(180, 600), font: 'Space Grotesk', fontSize: 22, color: _white, weight: FontWeight.w700),
    ],
  ),

  // ------------------------------------------------------------------ Creator
  MomentTemplate(
    id: 'newvideo',
    name: 'New video',
    category: TemplateCategory.creator,
    backdrop: () => _bd(BackdropStyle.mesh, 1),
    build: () => [
      TElement.text('NEW VIDEO', _o(180, 120), fontSize: 15, color: _white, bg: TextBg.pill, bgColor: _red, spacing: 3, weight: FontWeight.w900),
      TElement.slot(_o(180, 260), const Size(320, 180), shape: SlotShape.rounded, radius: 18, shadow: true, hint: 'Thumbnail'),
      TElement.text('I tried living like it\'s 1999 for a week', _o(180, 410), width: 310, font: 'Archivo Black', fontSize: 26, color: _white, weight: FontWeight.w400),
      TElement.text('Link in bio', _o(180, 500), fontSize: 15, color: _ink, bg: TextBg.sticker, bgColor: _white, role: TextRole.link),
      TElement.text('@yourchannel', _o(180, 590), fontSize: 14, color: _white, weight: FontWeight.w700, role: TextRole.mention),
    ],
  ),
  MomentTemplate(
    id: 'qna',
    name: 'Ask me anything',
    category: TemplateCategory.creator,
    backdrop: () => _bd(BackdropStyle.mesh, 0),
    build: () => [
      TElement.slot(_o(180, 150), const Size(120, 120), shape: SlotShape.circle, border: _white, borderWidth: 3, hint: 'You'),
      TElement.deco(DecoKind.rect, _o(180, 340), const Size(300, 170), color: _white, radius: 26),
      TElement.text('Ask me anything', _o(180, 290), font: 'Space Grotesk', fontSize: 26, color: _ink, weight: FontWeight.w700),
      TElement.text('Type something…', _o(180, 360), width: 250, fontSize: 16, color: const Color(0xFF858D9E), weight: FontWeight.w500, bg: TextBg.pill, bgColor: const Color(0xFFF0F1F4)),
      TElement.text('Answering tonight at 9 ✨', _o(180, 470), fontSize: 15, color: _white, weight: FontWeight.w700),
    ],
  ),
  MomentTemplate(
    id: 'collab',
    name: 'Collab',
    category: TemplateCategory.creator,
    backdrop: () => _bd(BackdropStyle.holo, 0, grain: .15),
    build: () => [
      TElement.slot(_o(110, 250), const Size(140, 140), shape: SlotShape.circle, border: _white, borderWidth: 4, shadow: true, hint: 'You'),
      TElement.slot(_o(250, 250), const Size(140, 140), shape: SlotShape.circle, border: _white, borderWidth: 4, shadow: true, hint: 'Partner'),
      TElement.text('×', _o(180, 250), font: 'Space Grotesk', fontSize: 44, color: _ink, weight: FontWeight.w700),
      TElement.text('SOMETHING\'S COMING', _o(180, 400), font: 'Bebas Neue', fontSize: 46, color: _ink, weight: FontWeight.w400, spacing: 2),
      TElement.text('@you  ×  @partner', _o(180, 450), fontSize: 15, color: _ink, weight: FontWeight.w800, role: TextRole.mention),
      TElement.text('#collab', _o(180, 580), fontSize: 14, color: _white, bg: TextBg.pill, bgColor: _ink, role: TextRole.tag),
    ],
  ),
  MomentTemplate(
    id: 'schedule',
    name: 'Weekly drops',
    category: TemplateCategory.creator,
    backdrop: () => _bd(BackdropStyle.grid, 6),
    build: () => [
      TElement.text('THIS WEEK', _o(180, 80), font: 'Monoton', fontSize: 36, color: _white, weight: FontWeight.w400, bg: TextBg.neon, bgColor: const Color(0xFFFF5DA2)),
      TElement.text('MON  ·  New episode\nWED  ·  Live Q&A\nFRI  ·  Studio vlog\nSUN  ·  Playlist drop', _o(180, 250), width: 300, font: 'Space Grotesk', fontSize: 21, color: _white, weight: FontWeight.w600, align: TextAlign.left, lineHeight: 1.7, bg: TextBg.highlight, bgColor: const Color(0xAA0B0425)),
      TElement.text('turn on notifications 🔔', _o(180, 420), fontSize: 14, color: _ink, bg: TextBg.sticker, bgColor: _white),
    ],
  ),
  MomentTemplate(
    id: 'bts',
    name: 'Behind the scenes',
    category: TemplateCategory.creator,
    backdrop: () => _bd(BackdropStyle.linear, 4, animate: false),
    build: () => [
      TElement.slot(_o(180, 320), templateSize, look: 'xpro2', hint: 'BTS shot'),
      TElement.deco(DecoKind.recDot, _o(34, 44), const Size(14, 14), color: _red),
      TElement.text('REC', _o(66, 44), fontSize: 15, color: _white, weight: FontWeight.w800, spacing: 2),
      TElement.text('00:42:17', _o(300, 44), font: 'Courier Prime', fontSize: 15, color: _white, weight: FontWeight.w700),
      TElement.text('BEHIND THE SCENES', _o(180, 560), font: 'Anton', fontSize: 34, color: _white, weight: FontWeight.w400, spacing: 1),
      TElement.text('day 3 on set', _o(180, 600), font: 'Caveat', fontSize: 24, color: _yellow, weight: FontWeight.w700),
    ],
  ),

  // ----------------------------------------------------------------- Trending
  MomentTemplate(
    id: 'dump',
    name: 'Photo dump',
    category: TemplateCategory.trending,
    trend: 'Monthly photo dumps',
    backdrop: () => _bd(BackdropStyle.paper, 2, grain: .3, animate: false),
    build: () => [
      TElement.text('october dump 📸', _o(180, 56), font: 'Space Grotesk', fontSize: 24, color: _ink, weight: FontWeight.w700),
      for (var i = 0; i < 6; i++)
        TElement.slot(_o(i.isEven ? 98 : 262, 175 + (i ~/ 2) * 180.0), const Size(156, 168),
            shape: SlotShape.rounded, radius: 10, rotation: (i.isEven ? -1 : 1) * .03),
    ],
  ),
  MomentTemplate(
    id: 'thisorthat',
    name: 'This or that',
    category: TemplateCategory.trending,
    trend: 'Poll-style choices',
    backdrop: () => _bd(BackdropStyle.checker, 0, animate: false),
    build: () => [
      TElement.text('this or that?', _o(180, 70), font: 'Archivo Black', fontSize: 30, color: _white, weight: FontWeight.w400, bg: TextBg.outline, bgColor: _ink),
      TElement.slot(_o(98, 320), const Size(150, 300), shape: SlotShape.rounded, radius: 20, border: _white, borderWidth: 3),
      TElement.slot(_o(262, 320), const Size(150, 300), shape: SlotShape.rounded, radius: 20, border: _white, borderWidth: 3),
      TElement.text('THIS', _o(98, 505), fontSize: 16, color: _ink, bg: TextBg.pill, bgColor: _white, spacing: 2),
      TElement.text('THAT', _o(262, 505), fontSize: 16, color: _ink, bg: TextBg.pill, bgColor: _white, spacing: 2),
    ],
  ),
  MomentTemplate(
    id: 'pov',
    name: 'POV',
    category: TemplateCategory.trending,
    trend: 'POV captions',
    backdrop: () => _bd(BackdropStyle.linear, 4, animate: false),
    build: () => [
      TElement.slot(_o(180, 320), templateSize, hint: 'Your shot'),
      TElement.text('POV: you finally booked the trip', _o(180, 430), width: 290, fontSize: 22, color: _ink, weight: FontWeight.w800, bg: TextBg.highlight, bgColor: _white),
    ],
  ),
  MomentTemplate(
    id: 'addyours',
    name: 'Add yours',
    category: TemplateCategory.trending,
    trend: 'Chain-prompt stickers',
    backdrop: () => _bd(BackdropStyle.mesh, 0),
    build: () => [
      TElement.slot(_o(180, 250), const Size(300, 380), shape: SlotShape.rounded, radius: 24, shadow: true),
      TElement.deco(DecoKind.rect, _o(180, 515), const Size(260, 86), color: _white, radius: 18),
      TElement.text('ADD YOURS', _o(180, 492), fontSize: 11, color: const Color(0xFF858D9E), weight: FontWeight.w800, spacing: 2),
      TElement.text('Show your view right now', _o(180, 522), width: 240, fontSize: 18, color: _ink, weight: FontWeight.w800),
      TElement.text('#addyours', _o(180, 600), fontSize: 13, color: _white, weight: FontWeight.w700, role: TextRole.tag),
    ],
  ),
  MomentTemplate(
    id: 'ratemyfit',
    name: 'Rate my fit',
    category: TemplateCategory.trending,
    trend: 'Fit checks',
    backdrop: () => _bd(BackdropStyle.sunburst, 3),
    build: () => [
      TElement.text('fit check', _o(180, 60), font: 'Permanent Marker', fontSize: 40, color: _ink, weight: FontWeight.w400),
      TElement.slot(_o(180, 315), const Size(250, 400), shape: SlotShape.rounded, radius: 20, border: _white, borderWidth: 4, shadow: true, hint: 'Outfit'),
      TElement.text('rate it 1–10', _o(180, 548), fontSize: 15, color: _ink, weight: FontWeight.w800),
      TElement.deco(DecoKind.rating, _o(180, 580), const Size(240, 12), color: _red, value: .8, color2: const Color(0x66FFFFFF)),
    ],
  ),
  MomentTemplate(
    id: 'recap',
    name: 'Year recap',
    category: TemplateCategory.trending,
    trend: 'Recaps & wrapped',
    backdrop: () => _bd(BackdropStyle.grid, 6),
    build: () => [
      TElement.text('2026', _o(180, 80), font: 'Monoton', fontSize: 70, color: _white, weight: FontWeight.w400, bg: TextBg.neon, bgColor: const Color(0xFF00E5FF)),
      TElement.text('RECAP', _o(180, 140), font: 'Bebas Neue', fontSize: 36, color: const Color(0xFFFF5DA2), weight: FontWeight.w400, spacing: 8),
      TElement.slot(_o(180, 270), const Size(300, 170), shape: SlotShape.rounded, radius: 16),
      TElement.slot(_o(105, 450), const Size(150, 150), shape: SlotShape.rounded, radius: 16),
      TElement.slot(_o(255, 450), const Size(150, 150), shape: SlotShape.rounded, radius: 16),
      TElement.text('12 cities · 1 big move · 0 regrets', _o(180, 575), width: 320, fontSize: 15, color: _white, weight: FontWeight.w700),
    ],
  ),

  // ---------------------------------------------------------- Quotes & advice
  MomentTemplate(
    id: 'quote',
    name: 'Quote card',
    category: TemplateCategory.quotes,
    backdrop: () => _bd(BackdropStyle.paper, 2, grain: .3, animate: false),
    build: () => [
      TElement.text('“', _o(70, 170), font: 'Playfair Display', fontSize: 140, color: _violet, weight: FontWeight.w900),
      TElement.text('Small steps every day add up to a life you’re proud of.', _o(180, 320), width: 290, font: 'DM Serif Display', fontSize: 32, color: _ink, weight: FontWeight.w400, lineHeight: 1.25),
      TElement.deco(DecoKind.line, _o(180, 450), const Size(40, 2), color: _violet),
      TElement.text('— your name', _o(180, 478), font: 'Cormorant Garamond', fontSize: 18, color: _ink, italic: true, weight: FontWeight.w600),
    ],
  ),
  MomentTemplate(
    id: 'notetoself',
    name: 'Note to self',
    category: TemplateCategory.quotes,
    backdrop: () => _bd(BackdropStyle.mesh, 3),
    build: () => [
      TElement.deco(DecoKind.rect, _o(180, 320), const Size(300, 330), color: const Color(0xFFFFFDF2), radius: 20),
      TElement.deco(DecoKind.rect, _o(180, 175), const Size(300, 40), color: const Color(0xFFFFE9A8), radius: 20),
      TElement.text('Notes', _o(80, 175), fontSize: 15, color: const Color(0xFFB8860B), weight: FontWeight.w800),
      TElement.text('note to self', _o(180, 232), width: 260, fontSize: 22, color: _ink, weight: FontWeight.w800, align: TextAlign.left),
      TElement.text('rest is productive.\nyou don’t have to earn a break.\ndrink water. text them back.', _o(180, 330), width: 260, fontSize: 17, color: const Color(0xFF3A3A3C), weight: FontWeight.w500, align: TextAlign.left, lineHeight: 1.5),
    ],
  ),
  MomentTemplate(
    id: 'tips',
    name: 'Three tips',
    category: TemplateCategory.quotes,
    backdrop: () => _bd(BackdropStyle.linear, 1, animate: false),
    build: () => [
      TElement.text('3 things I wish I knew sooner', _o(180, 110), width: 300, font: 'Archivo Black', fontSize: 28, color: _white, weight: FontWeight.w400),
      for (var i = 0; i < 3; i++) ...[
        TElement.deco(DecoKind.rect, _o(180, 255 + i * 110.0), const Size(310, 92), color: const Color(0x26FFFFFF), radius: 18),
        TElement.text('${i + 1}', _o(55, 255 + i * 110.0), font: 'Space Grotesk', fontSize: 34, color: [_mint, _pink, _yellow][i], weight: FontWeight.w700),
        TElement.text(['Start before you feel ready', 'Protect your mornings', 'Say no without a reason'][i],
            _o(200, 255 + i * 110.0), width: 230, fontSize: 17, color: _white, weight: FontWeight.w700, align: TextAlign.left),
      ],
      TElement.text('save this for later', _o(180, 600), fontSize: 13, color: _white, weight: FontWeight.w600, italic: true),
    ],
  ),
  MomentTemplate(
    id: 'affirmation',
    name: 'Affirmation',
    category: TemplateCategory.quotes,
    backdrop: () => _bd(BackdropStyle.aurora, 1, grain: .2),
    build: () => [
      TElement.text('daily affirmation', _o(180, 150), fontSize: 13, color: _cream, weight: FontWeight.w700, spacing: 4, upper: true),
      TElement.text('I am allowed to take up space', _o(180, 320), width: 300, font: 'Pacifico', fontSize: 38, color: _white, weight: FontWeight.w400, lineHeight: 1.35, bg: TextBg.neon, bgColor: _pink),
      TElement.text('breathe in · breathe out', _o(180, 520), font: 'Cormorant Garamond', fontSize: 20, color: _cream, italic: true, weight: FontWeight.w600),
    ],
  ),
];

/// A blank layout for "Start from scratch": one full-bleed photo slot.
MomentTemplate blankTemplate() => MomentTemplate(
      id: 'blank',
      name: 'Blank',
      category: TemplateCategory.creator,
      backdrop: () => _bd(BackdropStyle.mesh, 0),
      build: () => [],
    );

// Colour constants kept for templates added later.
// ignore: unused_element
const _palette = [_white, _ink, _cream, _violet, _pink, _peach, _blue, _mint, _yellow, _red];
