#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sourceDir = resolve(root, 'Resources/NeoFreeBirdMain/TwitterAppearance_TwitterAppearance.bundle/VectorImages/main');
const outputDir = resolve(root, 'Resources/GeneratedIcons');

const icons = {
  nfb_twitter_logo: 'twitter.svg',
  nfb_twitter_blue: 'twitter_blue_stroke.svg',
  nfb_loading: 'loading.svg',

  nfb_tab_home: 'home_stroke.svg',
  nfb_tab_home_selected: 'home.svg',
  nfb_tab_guide: 'search_stroke.svg',
  nfb_tab_guide_selected: 'search.svg',
  nfb_tab_grok: 'grok_icon_blackhole_stroke.svg',
  nfb_tab_grok_selected: 'grok_icon_blackhole.svg',
  nfb_tab_audiospace: 'spaces_stroke.svg',
  nfb_tab_audiospace_selected: 'spaces.svg',
  nfb_tab_communities: 'communities_stroke.svg',
  nfb_tab_communities_selected: 'communities.svg',
  nfb_tab_ntab: 'notifications_stroke.svg',
  nfb_tab_ntab_selected: 'notifications.svg',
  nfb_tab_messages: 'messages_stroke.svg',
  nfb_tab_messages_selected: 'messages.svg',
  nfb_tab_profile: 'person_stroke.svg',
  nfb_tab_profile_selected: 'person.svg',
  nfb_tab_media: 'media_tab_stroke.svg',
  nfb_tab_media_selected: 'media_tab.svg',

  nfb_home: 'home_stroke.svg',
  nfb_home_filled: 'home.svg',
  nfb_search: 'search_stroke.svg',
  nfb_hash: 'hash_stroke.svg',
  nfb_hash_filled: 'hash.svg',
  nfb_sparkle: 'sparkle.svg',
  nfb_notifications: 'notifications_stroke.svg',
  nfb_notifications_filled: 'notifications.svg',
  nfb_messages: 'messages_stroke.svg',
  nfb_messages_filled: 'messages.svg',
  nfb_profile: 'person_stroke.svg',
  nfb_profile_filled: 'person.svg',
  nfb_bookmark: 'bookmark_stroke.svg',
  nfb_bookmark_filled: 'bookmark.svg',
  nfb_lists: 'lists_stroke.svg',
  nfb_lists_filled: 'lists.svg',
  nfb_communities: 'communities_stroke.svg',
  nfb_people: 'communities_stroke.svg',
  nfb_people_group: 'people_group_stroke.svg',
  nfb_spaces: 'spaces_stroke.svg',
  nfb_notes: 'notes_stroke.svg',
  nfb_money: 'money_stroke.svg',
  nfb_account_add: 'account.svg',

  nfb_more: 'more.svg',
  nfb_play: 'play.svg',
  nfb_pause: 'pause.svg',
  nfb_speaker: 'speaker.svg',
  nfb_speaker_off: 'speaker_off.svg',
  nfb_playback_speed: 'media_playback_speed.svg',
  nfb_captions: 'closedcaptioning_stroke.svg',
  nfb_reply: 'reply_stroke.svg',
  nfb_retweet: 'retweet_stroke.svg',
  nfb_pin: 'pin.svg',
  nfb_like: 'heart_stroke.svg',
  nfb_like_filled: 'heart.svg',
  nfb_view_count: 'bar_chart.svg',
  nfb_share: 'share_stroke_bold.svg',

  nfb_settings: 'settings_stroke.svg',
  nfb_info: 'help_circle.svg',
  nfb_close: 'close.svg',
  nfb_arrow_left: 'arrow_left.svg',
  nfb_new_message: 'compose_dm.svg',

  nfb_camera: 'camera_stroke.svg',
  nfb_settings_stroke: 'settings_stroke.svg',
  nfb_media: 'photo_stroke.svg',
  nfb_video: 'camera_video_stroke.svg',
  nfb_photo_crop: 'photo_crop.svg',
  nfb_photo_enhance: 'photo_enhance.svg',
  nfb_filter: 'filter.svg',
  nfb_filter_filled: 'filter_fill.svg',
  nfb_sticker: 'sticker.svg',
  nfb_sticker_featured: 'sticker_featured.svg',
  nfb_sticker_recent: 'sticker_recent.svg',
  nfb_sticker_people: 'sticker_people.svg',
  nfb_sticker_symbols: 'sticker_symbols.svg',
  nfb_sticker_activity: 'sticker_activity.svg',
  nfb_alt_compose: 'alt_compose.svg',
  nfb_crop_original: 'crop_original.svg',
  nfb_crop_wide: 'crop_wide.svg',
  nfb_crop_square: 'crop_square.svg',
  nfb_crop_rotate: 'photo_rotate.svg',
  nfb_gif: 'gif_compose.svg',
  nfb_poll: 'bar_chart.svg',
  nfb_emoji: 'smile_circle.svg',
  nfb_calendar: 'calendar.svg',
  nfb_location: 'location_stroke.svg',
  nfb_link: 'link.svg',
  nfb_birthday: 'calendar.svg',
  nfb_check: 'checkmark.svg',
  nfb_chevron_down: 'chevron_down.svg',
  nfb_globe: 'globe.svg',
  nfb_plus: 'plus.svg',
  nfb_send: 'paper_airplane_share_stroke.svg',
  nfb_compose: 'compose.svg',
  nfb_feather: 'quill.svg',
  nfb_compose_square: 'compose.svg',
  nfb_verified: 'verified.svg'
};

function renderIcon(assetName, svgName) {
  const input = resolve(sourceDir, svgName);
  if (!existsSync(input)) throw new Error(`Missing TwitterAppearance vector: ${svgName}`);
  let svg = readFileSync(input, 'utf8');
  if (assetName !== 'nfb_verified') {
    if (/<svg[^>]*\sfill="none"/.test(svg)) {
      svg = svg.replace(/(<svg[^>]*?)\sfill="none"/, '$1 fill="#000000"');
    } else if (!/<svg[^>]*\sfill=/.test(svg)) {
      svg = svg.replace(/<svg([^>]*)>/, '<svg$1 fill="#000000">');
    }
  }

  const out = resolve(outputDir, `${assetName}.png`);
  const result = spawnSync('rsvg-convert', [
    '--format=png',
    '--width', '96',
    '--height', '96',
    '--output', out
  ], { input: svg, encoding: 'utf8' });

  if (result.status !== 0) {
    throw new Error(result.stderr || `rsvg-convert failed for ${assetName}`);
  }
}

mkdirSync(outputDir, { recursive: true });
for (const [assetName, svgName] of Object.entries(icons)) {
  renderIcon(assetName, svgName);
}
