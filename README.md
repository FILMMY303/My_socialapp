# MySocial (appsocial)

A Flutter social network app (feed, reactions, comments, chat, groups and
pages, notifications) backed by Supabase, with offline-first posting.

## Download and links

| | |
|---|---|
| Source code | https://github.com/FILMMY303/My_socialapp |
| Android APK | [Releases](https://github.com/FILMMY303/My_socialapp/releases/latest): download `app-release.apk`, open it on the phone and allow "Install unknown apps" |
| Web | `flutter run -d chrome`, or deploy `build/web` |
| iOS / TestFlight | Not published. Building for iOS needs a Mac with Xcode and an Apple Developer account; see [iOS](#ios) |

The APK talks to the Supabase project whose URL and publishable key were in
`.env` at build time.

## Configure Supabase

1. Create a Supabase project.
2. Copy the project URL and the public publishable key from the project API settings.
3. Add both values to the root `.env` file:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-public-publishable-key
```

The app loads this file on startup. `.env` is excluded from Git; `.env.example`
shows the required variable names. Do not put a `service_role` key in a Flutter
app; use only the public publishable key.

Login and registration use Supabase Auth with email and password. Registration
saves the username in the user's `user_metadata`. To let users sign in
immediately after registering, open **Authentication > Sign In / Providers >
Email** in the Supabase dashboard and turn off **Confirm email**. This setting
is enforced by Supabase Auth and cannot be overridden by the Flutter client.
When it is off, a successful registration creates a session and the app opens
the signed-in experience automatically. The profile screen displays the
signed-in user's email and username and includes sign out.

## Supabase Auth settings

- **Password reset (6-digit code):** in **Authentication > Email Templates >
  Reset Password**, put the code in the email body, for example
  `<p>Your code: <b>{{ .Token }}</b></p>`. Under **Providers > Email**, set
  **Email OTP Length** to 6.
- The free Supabase email service sends only a few emails per hour; set up
  custom SMTP for real use.

## Database setup

Apply the migrations in `supabase/migrations/` in filename order, for example by
pasting each file into the Supabase dashboard SQL Editor and running it. Each
one is safe to run again.

1. `20261007030000_create_posts.sql`: creates `posts` (skipped if it exists).
2. `20261007040000_posts_add_username.sql`: adds `posts.username`.
3. `20261007050000_crud_posts_comments_reactions.sql`: adds edit and delete
   permissions for posts, comments and reactions, makes deleting a post also
   delete its comments and reactions, and creates a `profiles` row for every
   user.
4. `20261008010000_social_features.sql`: adds the following.
   - Public and private profiles, and follows (a private profile needs to
     approve each follower).
   - Image and video posts, emoji reactions, and hashtags.
   - Groups and pages.
   - 1-1 chat with live updates.
   - Post reports.
   - Storage buckets: `avatars`, `post-media`, and `chat-media` (private).
5. `20261008020000_chat_mutes.sql`: adds `chat_mutes`, which turns off message
   notifications from a specific person.
6. `20261008030000_groups_comments_notifications_saved.sql`: adds the
   following.
   - Group pictures and banners, staff roles, kicking members, and report
     review for group owners and staff.
   - Comment replies with photos or videos.
   - `notifications`, filled by database triggers.
   - `saved_posts`, plus `profiles.saved_public`.
7. `20261008040000_blocks_shares_more_notifications.sql`: adds the following.
   - `blocks`: hides posts, comments, messages and follows in both
     directions.
   - Sharing posts (`posts.shared_post_id`).
   - Notifications for comments, replies, reactions and shares.
8. `20261027010000_group_notification_settings.sql`: adds
   `group_members.notify` (pages notify by default, groups don't),
   the `group_post` notification type, and `set_group_notifications()` so
   members can change only their own setting.

## Features

| Feature | What you can do | Where |
|---|---|---|
| Accounts | Sign up, log in, edit your profile (photo, username, display name, bio) | Profile → ⚙ Settings → Edit profile |
| Forgot password | Get a 6-digit code by email, enter it, set a new password. Works the same on web and phones (no links) | Login → forgot password? |
| Settings | Edit profile, blocked users, dark mode, message notifications (desktop browsers), group and page notifications | Profile → ⚙ |
| Dark mode | Light by default; the choice is remembered on web and phones | Settings → Dark mode |
| Posts | Write text with a photo or a video of up to 2 minutes, edit, delete | **+** button, `...` menu |
| Feed | Timeline sorted by time, pull to refresh | Home tab |
| Reactions | 👍 ❤️ 😆 😮 😢 😡 👎 (tap Like, or hold it to pick) | Under each post |
| Comments | Add, edit, delete | Comment button |
| Chat (1-1) | Send text, photos and videos; unsend; seen status; live updates | Message icon, or Message on a profile |
| Message notifications | Pop-up banner in the app, a browser notification when the tab is in the background, and an unread badge. Mute anyone with the 🔔 button in their chat | Any screen, Messages icon |
| Groups and pages | Create, join, edit, leave, delete; each has its own feed | Groups tab |
| Privacy and follows | Public or private profile; follow and unfollow; accept or decline follow requests | Profile, bell icon |
| Search | People by name, posts by `#tag` | Search tab, or tap a #tag |
| Reports | Report a post with a reason; it is hidden for you. Group owners and staff review reports on their group's posts (keep or remove) | `...` menu → Report post; group page → Reports |
| Group management | Owner: set the group picture and banner, make members staff (or remove staff), kick anyone. Staff: kick members, review reports | Group page → Edit / Members |
| Comment replies | Reply to a comment (threads stay one level deep, with an @mention); add a photo or video to a comment | Comments → Reply |
| Notifications | New followers, follow requests (accept or decline here), new posts from people you follow and from groups and pages you turned on; a red dot on the bell and a live banner | Bell icon on Home |
| Group and page notifications | Turn new-post notifications on or off per group or page | Group page → 🔔, or Settings → Groups & pages |
| Saved posts | Save or unsave from the `...` menu; a Saved tab on your profile. Edit Profile → "Show my saved posts" lets others see it | Profile → Saved |
| Block users | Neither person sees the other's posts or comments, and they can't message or follow each other. The blocked person isn't told. Unblock any time | Profile → ⋮ → Block; Settings → Blocked users |
| Share | Share a post to your timeline with an optional caption. Sharing a share shares the original. If the original is deleted, the share says it's unavailable | Share button |
| More notifications | Someone commented on your post, replied to your comment, reacted (with the emoji), or shared your post | Bell icon |
| Infinite scroll | Feeds load older posts as you scroll; refreshing keeps what you already loaded | All feeds |

Users can only change their own content. The app checks this, and Supabase
row-level security enforces it. Group owners and admins can also remove posts
and members. On a page, only the owner and admins can post.

**Offline behavior:** posts, comments and reactions (including in groups) save
to the local database first and sync later (see below). Profiles, follows,
groups, chat, search, reports and media uploads need a connection; they show a
clear error with a retry button when offline.

## Architecture: UI → local DB → cloud

```
UI (screens) ──► SocialRepository ──► LocalDatabase (sembast)
     ▲                 │                 posts / comments / reactions / outbox
     │                 ▼
     └── streams ◄── sync: outbox ──► Supabase (posts, comments, post_reactions)
                       pull: Supabase ──► LocalDatabase
```

- **Local-first writes.** Every change is written to the local database and
  added to an `outbox` in a single transaction, so the UI updates at once and
  works offline. IDs are client-generated UUIDs, so a row keeps the same ID
  locally and in the cloud.
- **Sync.** The outbox is sent in order after each change, every 20 seconds
  while changes are pending, and on pull-to-refresh. Sends are idempotent
  (upserts and filtered deletes), so retries are safe.
- **Pull.** Pull-to-refresh, app start and a periodic timer download the latest
  50 posts with their comments and reactions. Rows with unsent local changes
  are not overwritten.
- **Storage.** Local data lives in IndexedDB on the web and in a file on
  mobile and desktop, with one database per signed-in user.

Code layout:

- `lib/data/local/local_database.dart`: local schema
- `lib/data/remote/remote_data_source.dart`: Supabase calls
- `lib/data/repositories/social_repository.dart`: CRUD, outbox and sync, with
  feeds scoped to home, a group, a user or a tag
- `lib/data/services/`: online-only features (profiles and follows, groups,
  chat, media, reports)
- `lib/data/repository_scope.dart`: `AppServices`, which gives screens access
  to all of the above
- `lib/core/errors/app_exception.dart`: error mapping
- `test/social_repository_test.dart`: repository tests
- `test/widget_smoke_test.dart`: checks that the screens render

## Error handling

- **Validation:** empty text and text over the length limit (2,000 characters
  for posts, 1,000 for comments) are rejected before saving, and the message
  appears next to the input.
- **Offline, timeouts and server errors:** the change stays in the outbox. A
  banner shows "Offline · N change(s) saved on this device" with a Retry
  button. Network calls time out after 15 seconds.
- **Rejected changes** (permission, constraint, or a row deleted by someone
  else): the change is dropped, the row is restored from the cloud, and a red
  snackbar explains why.
- **Expired session:** treated as temporary and retried after the session
  refreshes.
- **Uploads:** images over 5 MB, videos over 50 MB and videos longer than
  2 minutes are rejected before uploading (the length is checked in the app,
  not by Supabase), and wrong file types get a clear message. If saving the post
  fails after the upload, the uploaded file is deleted.
- **Online-only screens** (profile, groups, chat, search): load errors show the
  message with a Try again button. Action errors (follow, join, send, report)
  show a snackbar, or appear inside the open dialog.
- **Local storage failure:** shows an error screen with Try again and Sign
  out.
- Supabase error codes (`23505`, `23503`, `42501`, `PGRST2xx`, ...) are turned
  into readable messages.

## Build and test

```bash
flutter pub get
flutter test                      # unit and widget tests
flutter run -d chrome             # web
flutter build web
```

### Android

Needs JDK 17 or newer (JDK 21 recommended) and the Android SDK.

```bash
flutter config --jdk-dir <path-to-jdk>
flutter doctor --android-licenses
flutter run -d <device-id>        # see `flutter devices`
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
```

The release build is signed with the debug key, which is fine for sharing an
APK but not for Google Play. The first Gradle build downloads several GB.

### iOS

Requires macOS and Xcode. Run `flutter build ipa`, then upload to App Store
Connect (Xcode Organizer or Transporter) and add testers in TestFlight. This
needs a paid Apple Developer account and a unique bundle ID in place of
`com.example.appsocial`.

### App icon

`flutter test tool/generate_app_icons.dart` redraws the Android, iOS and web
icons (white "s" on #059669).

## Known setup issue: spaces in paths

The project and Flutter SDK live under `advance Programing`, which contains a
space. Some packages' native build hooks fail on such paths, so `pubspec.yaml`
pins `path_provider_foundation` to 2.5.1. Moving the project and SDK to a path
without spaces removes the need for the pin.
