package PearlBee;
# ABSTRACT: PerlBee Blog platform

use Dancer2 0.163000;
use Dancer2::Plugin::DBIC;
use Dancer2::Plugin::reCAPTCHA;

# Other used modules
use DateTime;
use JSON;

# Included controllers

# Common controllers
use PearlBee::Authentication;
use PearlBee::Authorization;
use PearlBee::Dashboard;
use PearlBee::REST;
use PearlBee::RSS;
use PearlBee::ResetPassword;
use PearlBee::Search;

# Admin controllers
use PearlBee::Admin;

# Author controllers
use PearlBee::Author::Post;
use PearlBee::Author::Comment;

use PearlBee::Helpers::Util qw(generate_crypted_filename map_posts create_password);
use PearlBee::Helpers::Pagination qw(get_total_pages get_previous_next_link);
use PearlBee::Helpers::Captcha;

our $VERSION = '0.1';
use Data::Dumper;
  
=head

Prepare the blog path

=cut

hook 'before' => sub {
  session app_url   => config->{app_url} unless ( session('app_url') );
  session blog_name => resultset('Setting')->first->blog_name unless ( session('blog_name') );
  session multiuser => resultset('Setting')->first->multiuser;
};

=head

Blog assets - XXX this should be managed by nginx or something.

=cut

set public_dir => path(config->{user_assets});
set avatar_dir => path(config->{user_avatars});

get '/users/*' => sub {
    my ( $file ) = splat;

    send_file $file;
};

get '/avatars/*' => sub {
    my ( $file ) = splat;

    send_file $file;
};

=head

Home page

=cut

get '/' => sub {
  my $nr_of_rows  = config->{posts_on_page} || 5; # Number of posts per page
  my @posts       = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => $nr_of_rows });
  my $nr_of_posts = resultset('Post')->search({ status => 'published' })->count;
  my @tags        = resultset('View::PublishedTags')->all();
  my @categories  = resultset('View::PublishedCategories')->search({ name => { '!=' => 'Uncategorized'} });
  my @recent      = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => 3 });
  my @popular     = resultset('View::PopularPosts')->search({}, { rows => 3 });

  # extract demo posts info
  my @mapped_posts = map_posts(@posts);

  my $total_pages                 = get_total_pages($nr_of_posts, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link(1, $total_pages);
  
    template 'index',
      {
        posts         => \@mapped_posts,
        recent        => \@recent,
        popular       => \@popular,
        tags          => \@tags,
        categories    => \@categories,
        page          => 1,
        total_pages   => $total_pages,
        previous_link => $previous_link,
        next_link     => $next_link
    };
};

=head

Home page

=cut

get '/page/:page' => sub {

  my $nr_of_rows  = config->{posts_on_page} || 10; # Number of posts per page
  my $page        = route_parameters->{'page'};
  my @posts       = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => $nr_of_rows, page => $page });
  my $nr_of_posts = resultset('Post')->search({ status => 'published' })->count;
  my @tags        = resultset('View::PublishedTags')->all();
  my @categories  = resultset('View::PublishedCategories')->search({ name => { '!=' => 'Uncategorized'} });
  my @recent      = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => 3 });
  my @popular     = resultset('View::PopularPosts')->search({}, { rows => 3 });

  # extract demo posts info
  my @mapped_posts = map_posts(@posts);

  # Calculate the next and previous page link
  my $total_pages                 = get_total_pages($nr_of_posts, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link($page, $total_pages);

  if ( param('format') ) {
    my $json = JSON->new;
    $json->allow_blessed(1);
    $json->convert_blessed(1);
    $json->encode([
      @mapped_posts   
    ]); 
  }     
  else {

    template 'index',
      {
        posts         => \@mapped_posts,
        recent        => \@recent,
        popular       => \@popular,
        tags          => \@tags,
        categories    => \@categories,
        page          => $page,
        total_pages   => $total_pages,
        previous_link => $previous_link,
        next_link     => $next_link
    };
  }
};


=head

View post method

=cut

get '/post/:slug' => sub {

  my $slug       = route_parameters->{'slug'};
  my $post       = resultset('Post')->find({ slug => $slug });
  my $settings   = resultset('Setting')->first;
  my @tags       = resultset('View::PublishedTags')->all();
  my @categories = resultset('View::PublishedCategories')->search({ name => { '!=' => 'Uncategorized'} });
  my @recent     = resultset('Post')->get_recent_posts();
  my @popular    = resultset('View::PopularPosts')->search({}, { rows => 3 });
  my @comments   = resultset('Comment')->get_approved_comments_by_post_id($post->id);

  template 'post',
    {
      post       => $post,
      recent     => \@recent,
      popular    => \@popular,
      categories => \@categories,
      comments   => \@comments,
      setting    => $settings,
      tags       => \@tags,
      recaptcha  => recaptcha_display(),
    };
};

=head

Add a comment method

=cut

post '/comment/add' => sub {

  my $parameters  = body_parameters;
  my $fullname    = $parameters->{'fullname'};
  my $post_id     = $parameters->{'id'};
  my $secret      = $parameters->{'secret'};
  my @comments    = resultset('Comment')->search({ post_id => $post_id, status => 'approved', reply_to => undef });
  my $post        = resultset('Post')->find( $post_id );
  my @categories  = resultset('Category')->all();
  my @recent      = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => 3 });
  my @popular     = resultset('View::PopularPosts')->search({}, { rows => 3 });
  my $user        = session('user');

  $parameters->{'reply_to'} = $1 if ($parameters->{'in_reply_to'} =~ /(\d+)/);
  if ($parameters->{'reply_to'}) {
    my $comm = resultset('Comment')->find({ id => $parameters->{'reply_to'} });
    if ($comm) {
      $parameters->{'reply_to_content'} = $comm->content;
      $parameters->{'reply_to_user'} = $comm->fullname;
    }
  }

  my $template_params = {
    post        => $post,
    categories  => \@categories,
    popular     => \@popular,
    recent      => \@recent,
    warning     => 'The secret code is incorrect'
  };

  my $response = param('g-recaptcha-response');
  my $result = recaptcha_verify($response);

  if ( $result->{success} || $ENV{CAPTCHA_BYPASS} ) {

    # The user entered the correct secret code
    eval {

      # If the person who leaves the comment is either the author or the admin the comment is automaticaly approved

      my $comment = resultset('Comment')->can_create( $parameters, $user );

      # Notify the author that a new comment was submited
      my $author = $post->user;

      Email::Template->send( config->{email_templates} . 'new_comment.tt',
      {
          From    => config->{default_email_sender},
          To      => $author->email,
          Subject => ($parameters->{'reply_to'} ? 'A comment reply was submitted to your post' : 'A new comment was submitted to your post'),

          tt_vars => {
            fullname         => $fullname,
            title            => $post->title,
            comment          => $parameters->{'comment'},
            signature        => config->{email_signature},
            post_url         => config->{app_url} . '/post/' . $post->slug,
            app_url          => config->{app_url},
            reply_to_content => $parameters->{'reply_to_content'} || '',
            reply_to_user    => $parameters->{'reply_to_user'}    || '',
          },
      }) or error "Could not send the email";
    };
    error $@ if ( $@ );

    # Grab the approved comments for this post
    @comments = resultset('Comment')->search({ post_id => $post->id, status => 'approved', reply_to => undef }) if ( $post );

    delete $template_params->{warning};
    delete $template_params->{in_reply_to};

    if (($post->user_id && $user && $post->user_id == $user->{id}) or ($user && $user->{is_admin})) {
      $template_params->{success} = 'Your comment has been submited. Thank you!';
    } else {
      $template_params->{success} = 'Your comment has been submited and it will be displayed as soon as the author accepts it. Thank you!';
    }
  }
  else {
    # The secret code inncorrect
    # Repopulate the fields with the data

    $template_params->{fields} = $parameters;
  }

  foreach my $comment (@comments) {
    my @comment_replies = resultset('Comment')->search({ reply_to => $comment->id, status => 'approved' }, {order_by => { -asc => "comment_date" }});
    foreach my $reply (@comment_replies) {
      my $el;
      map { $el->{$_} = $reply->$_ } ('avatar', 'fullname', 'comment_date', 'content');
      $el->{uid}->{username} = $reply->uid->username if $reply->uid;
      push(@{$comment->{comment_replies}}, $el);
    }
  }
  $template_params->{comments} = \@comments;
  $template_params->{recaptcha} = recaptcha_display();

  template 'post', $template_params;

};

=head

List all posts by selected category

=cut

get '/posts/category/:slug' => sub {

  my $nr_of_rows  = config->{posts_on_page} || 5; # Number of posts per page
  my $slug        = route_parameters->{'slug'};
  my @posts       = resultset('Post')->search({ 'category.slug' => $slug, 'status' => 'published' }, { join => { 'post_categories' => 'category' }, order_by => { -desc => "created_date" }, rows => $nr_of_rows });
  my $nr_of_posts = resultset('Post')->search({ 'category.slug' => $slug, 'status' => 'published' }, { join => { 'post_categories' => 'category' } })->count;
  my @tags        = resultset('View::PublishedTags')->all();
  my @categories  = resultset('View::PublishedCategories')->search({ name => { '!=' => 'Uncategorized'} });
  my @recent      = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => 3 });
  my @popular     = resultset('View::PopularPosts')->search({}, { rows => 3 });

  # extract demo posts info
  my @mapped_posts = map_posts(@posts);

  # Calculate the next and previous page link
  my $total_pages                 = get_total_pages($nr_of_posts, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link(1, $total_pages, '/posts/category/' . $slug);

  # Extract all posts with the wanted category
  template 'index',
      {
        posts         => \@mapped_posts,
        recent        => \@recent,
        popular       => \@popular,
        tags          => \@tags,
        page          => 1,
        categories    => \@categories,
        total_pages   => $total_pages,
        next_link     => $next_link,
        previous_link => $previous_link,
        posts_for_category => $slug
    };
};

=head

List all posts by selected category

=cut

get '/posts/category/:slug/page/:page' => sub {

  my $nr_of_rows  = config->{posts_on_page} || 5; # Number of posts per page
  my $page        = route_parameters->{'page'};
  my $slug        = route_parameters->{'slug'};
  my @posts       = resultset('Post')->search({ 'category.slug' => $slug, 'status' => 'published' }, { join => { 'post_categories' => 'category' }, order_by => { -desc => "created_date" }, rows => $nr_of_rows, page => $page });
  my $nr_of_posts = resultset('Post')->search({ 'category.slug' => $slug, 'status' => 'published' }, { join => { 'post_categories' => 'category' } })->count;
  my @tags        = resultset('View::PublishedTags')->all();
  my @categories  = resultset('View::PublishedCategories')->search({ name => { '!=' => 'Uncategorized'} });
  my @recent      = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => 3 });
  my @popular     = resultset('View::PopularPosts')->search({}, { rows => 3 });

  # extract demo posts info
  my @mapped_posts = map_posts(@posts);

  # Calculate the next and previous page link
  my $total_pages                 = get_total_pages($nr_of_posts, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link($page, $total_pages, '/posts/category/' . $slug);

  template 'index',
      {
        posts              => \@mapped_posts,
        recent             => \@recent,
        popular            => \@popular,
        tags               => \@tags,
        categories         => \@categories,
        page               => $page,
        total_pages        => $total_pages,
        next_link          => $next_link,
        previous_link      => $previous_link,
        posts_for_category => $slug
    };
};

=head

List all posts by selected author

=cut

get '/posts/user/:username' => sub {

  my $nr_of_rows  = config->{posts_on_page} || 5; # Number of posts per page
  my $username    = route_parameters->{'username'};
  my $user         = resultset('User')->find({username => $username});
  unless ($user) {
    # we did not identify the user
  }
  my @posts       = resultset('Post')->search({ 'user_id' => $user->id, 'status' => 'published' }, { order_by => { -desc => "created_date" }, rows => $nr_of_rows });
  my $nr_of_posts = resultset('Post')->search({ 'user_id' => $user->id, 'status' => 'published' })->count;
  my @tags        = resultset('View::PublishedTags')->all();
  my @categories  = resultset('View::PublishedCategories')->search({ name => { '!=' => 'Uncategorized'} });
  my @recent      = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => 3 });
  my @popular     = resultset('View::PopularPosts')->search({}, { rows => 3 });

  # extract demo posts info
  my @mapped_posts = map_posts(@posts);
  my $movable_type_url = config->{movable_type_url};
  my $app_url = config->{app_url};

  for my $post ( @mapped_posts ) {
    $post->{content} =~ s{$movable_type_url}{$app_url}g;
  }


  # Calculate the next and previous page link
  my $total_pages                 = get_total_pages($nr_of_posts, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link(1, $total_pages, '/posts/user/' . $username);

  # Extract all posts with the wanted category
  template 'index',
      {
        posts          => \@mapped_posts,
        recent         => \@recent,
        popular        => \@popular,
        tags           => \@tags,
        page           => 1,
        categories     => \@categories,
        total_pages    => $total_pages,
        next_link      => $next_link,
        previous_link  => $previous_link,
        posts_for_user => $username,
    };
};

=head

List all posts by selected category

=cut

get '/posts/user/:username/page/:page' => sub {

  my $nr_of_rows  = config->{posts_on_page} || 5; # Number of posts per page
  my $username    = route_parameters->{'username'};
  my $user        = resultset('User')->find({username => $username});
  unless ($user) {
    # we did not identify the user
  }
  my $page        = route_parameters->{'page'};
  my @posts       = resultset('Post')->search({ 'user_id' => $user->id, 'status' => 'published' }, { order_by => { -desc => "created_date" }, rows => $nr_of_rows, page => $page });
  my $nr_of_posts = resultset('Post')->search({ 'user_id' => $user->id, 'status' => 'published' })->count;
  my @tags        = resultset('View::PublishedTags')->all();
  my @categories  = resultset('View::PublishedCategories')->search({ name => { '!=' => 'Uncategorized'} });
  my @recent      = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => 3 });
  my @popular     = resultset('View::PopularPosts')->search({}, { rows => 3 });

  # extract demo posts info
  my @mapped_posts = map_posts(@posts);

  # Calculate the next and previous page link
  my $total_pages                 = get_total_pages($nr_of_posts, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link($page, $total_pages, '/posts/user/' . $username);

  template 'index',
      {
        posts         => \@mapped_posts,
        recent        => \@recent,
        popular       => \@popular,
        tags          => \@tags,
        categories    => \@categories,
        page          => $page,
        total_pages   => $total_pages,
        next_link     => $next_link,
        previous_link => $previous_link,
        posts_for_user => $username,
    };
};

=head

List all posts by selected tag

=cut

get '/posts/tag/:slug' => sub {

  my $nr_of_rows  = config->{posts_on_page} || 5; # Number of posts per page
  my $slug        = route_parameters->{'slug'};
  my @posts       = resultset('Post')->search({ 'tag.slug' => $slug, 'status' => 'published' }, { join => { 'post_tags' => 'tag' }, order_by => { -desc => "created_date" }, rows => $nr_of_rows });
  my $nr_of_posts = resultset('Post')->search({ 'tag.slug' => $slug, 'status' => 'published' }, { join => { 'post_tags' => 'tag' } })->count;
  my @tags        = resultset('View::PublishedTags')->all();
  my @categories  = resultset('View::PublishedCategories')->search({ name => { '!=' => 'Uncategorized'} });
  my @recent      = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => 3 });
  my @popular     = resultset('View::PopularPosts')->search({}, { rows => 3 });

  # extract demo posts info
  my @mapped_posts = map_posts(@posts);

  # Calculate the next and previous page link
  my $total_pages                 = get_total_pages($nr_of_posts, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link(1, $total_pages, '/posts/tag/' . $slug);

  template 'index',
      {
        posts         => \@mapped_posts,
        recent        => \@recent,
        popular       => \@popular,
        tags          => \@tags,
        page          => 1,
        categories    => \@categories,
        total_pages   => $total_pages,
        next_link     => $next_link,
        previous_link => $previous_link,
        posts_for_tag => $slug
    };
};

=head

List all posts by selected tag

=cut

get '/posts/tag/:slug/page/:page' => sub {

  my $nr_of_rows  = config->{posts_on_page} || 5; # Number of posts per page
  my $page        = route_parameters->{'page'};
  my $slug        = route_parameters->{'slug'};
  my $tag         = resultset('Tag')->find({ slug => $slug });
  my @posts       = resultset('Post')->search({ 'tag.slug' => $slug, 'status' => 'published' }, { join => { 'post_tags' => 'tag' }, order_by => { -desc => "created_date" }, rows => $nr_of_rows });
  my $nr_of_posts = resultset('Post')->search({ 'tag.slug' => $slug, 'status' => 'published' }, { join => { 'post_tags' => 'tag' } })->count;
  my @tags        = resultset('View::PublishedTags')->all();
  my @categories  = resultset('View::PublishedCategories')->search({ name => { '!=' => 'Uncategorized'} });
  my @recent      = resultset('Post')->search({ status => 'published' },{ order_by => { -desc => "created_date" }, rows => 3 });
  my @popular     = resultset('View::PopularPosts')->search({}, { rows => 3 });

  # extract demo posts info
  my @mapped_posts = map_posts(@posts);

  # Calculate the next and previous page link
  my $total_pages                 = get_total_pages($nr_of_posts, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link($page, $total_pages, '/posts/tag/' . $slug);

  template 'index',
      {
        posts         => \@mapped_posts,
        recent        => \@recent,
        popular       => \@popular,
        tags          => \@tags,
        page          => $page,
        categories    => \@categories,
        total_pages   => $total_pages,
        next_link     => $next_link,
        previous_link => $previous_link,
        posts_for_tag => $slug
    };
};

get '/register' => sub {
   
  template 'register', {
      recaptcha  => recaptcha_display(),
  };

};

get '/register_success' => sub {
   
  template 'register_success';

};

get '/register_done' => sub {
   
  template 'register_done';

};

get '/password_recovery' => sub {

  template 'password_recovery';

};

get '/sign-up' => sub {

  template 'signup', {
    recaptcha => recaptcha_display()
  };
};

post '/sign-up' => sub {
  my $params = body_parameters;

  my $err;

  my $template_params = {
    username        => $params->{'username'},
    email           => $params->{'email'},
    name            => $params->{'name'},
  };

  my $response = $params->{'g-recaptcha-response'};
  my $result = recaptcha_verify($response);


  if ( $result->{success} || $ENV{CAPTCHA_BYPASS} ) {
    # The user entered the correct secrete code
    eval {

      my $u = resultset('User')->search( { email => $params->{'email'} } )->first;
      if ($u) {
        $err = "An user with this email address already exists.";
      } else {
        $u = resultset('User')->search( { username => $params->{'username'} } )->first;
        if ($u) {
          $err = "The provided username is already in use.";
        } else {

          # Create the user
          if ( $params->{'username'} ) {

            # Set the proper timezone
            my $dt       = DateTime->now;
            my $settings = resultset('Setting')->first;
            $dt->set_time_zone( $settings->timezone );

            my ($password, $pass_hash) = create_password();#, $salt) = create_password();

            resultset('User')->create({
              username        => $params->{username},
              password        => $pass_hash,
              email           => $params->{'email'},
              name            => $params->{'name'},
              register_date   => join (' ', $dt->ymd, $dt->hms),
              role            => 'author',
              status          => 'pending'
            });

            # Notify the author that a new comment was submited
            my $first_admin = resultset('User')->search( {role => 'admin', status => 'activated' } )->first;

            Email::Template->send( config->{email_templates} . 'new_user.tt',
            {
              From     => config->{default_email_sender},
              To       => $first_admin->email,
              Subject  => 'A new user applied as an author to the blog',

              tt_vars  => {
                name             => $params->{'name'},
                username         => $params->{'username'},
                email            => $params->{'email'},
                signature        => config->{email_signature},
                blog_name        => session('blog_name'),
                app_url          => session('app_url'),
              }
            }) or error "Could not send the email";

          } else {
            $err = 'Please provide a username.';
          }
        }
      }
    };
    error $@ if ( $@ );
  }
  else {
    # The secret code inncorrect
    # Repopulate the fields with the data
    $err = "Invalid secret code.";
  }

  if ($err) {
    $template_params->{warning} = $err if $err;
    $template_params->{recaptcha} = recaptcha_display();

    template 'signup', $template_params;
  } else {
    template 'notify', {success => 'The user was created and it is waiting for admin approval.'};
  }
};

1;
