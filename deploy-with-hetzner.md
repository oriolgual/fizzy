# How to deploy Fizzy with Terraform and Hetzner

## Prerequisities

1. A Hetzner account
1. Terraform installed
1. `s3api` installed
1. Docker installed and running
1. A fizzy fork cloned

1. Open the [Hetzner console](https://console.hetzner.com/projects)
1. Create a new project, name it "Fizzy"
1. Open the project, and go to Security -> API tokens. Generate a new Read & Write one. You can name it "Fizzy infra".
1. Create a "terraform.tfvars" and paste the api key, along with the other data
1. Go to Object Storage, create a new bucket and credentials TODO

Run terraform init and terraform apply. It will generate some output, we need to do a couple of things:

Update your `~./ssh/config` and add:

```
Host fizzy
  HostName fizzy.yourdomain.com
  User kamal
  Port 2222
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519
```

Go to your domain registrar and add an Alias record with the IP you got from Hetzner:

`fizzy IN A IP.FROM.HETZ.NER`

clone your fizzy fork and run `bin/setup`

Changes to `config/deploy.yml`:

Change line 10: `- fizzy.example.com  # Set your server name here` to your server name.
Change ssh config to:

```yml
ssh:
  user: kamal
  port: 2222
```

And also the proxy configuration:

```yml
proxy:
  ssl: true # Set this to false if you *don't* want SSL
  host: fizzy.gual.me # Set your server name here to use automatic SSL
```

The env variables:

```yml
env:
    - VAPID_PRIVATE_KEY
    - SMTP_USERNAME
    - SMTP_PASSWORD
    - SMTP_PORT
    - SMTP_DOMAIN
    - S3_ACCESS_KEY_ID
    - S3_SECRET_ACCESS_KEY
    - S3_BUCKET
    - S3_ENDPOINT
    - S3_REGION
  clear:
    MAILER_FROM_ADDRESS: support@example.com # The email "from" address that Fizzy sends email from
    SMTP_ADDRESS: mail.example.com # The SMTP server you'll use to send email
    SOLID_QUEUE_IN_PUMA: true # Run background jobs in the app container
    ACTIVE_STORAGE_SERVICE: s3
    CSP_CONNECT_SRC: https://fsn1.your-objectstorage.com
    S3_FORCE_PATH_STYLE: "true"
```

Finally, the volumes to match our terraform plan:

```yml
volumes:
  - "/mnt/fizzy_storage:/rails/storage"
```

We also need to add the configuration for the uploads:

Add the following to `config/storage.oss.yml`:

```yaml
s3:
  service: S3
  access_key_id: <%= ENV["S3_ACCESS_KEY_ID"] %>
  bucket: <%= ENV["S3_BUCKET"] || "fizzy-#{Rails.env}-activestorage" %>
  endpoint: <%= ENV["S3_ENDPOINT"] %>
  force_path_style: <%= ENV["S3_FORCE_PATH_STYLE"] == "true" %>
  region: <%= ENV.fetch("S3_REGION", "us-east-1") %>
  request_checksum_calculation: <%= ENV.fetch("S3_REQUEST_CHECKSUM_CALCULATION", "when_supported") %>
  response_checksum_validation: <%= ENV.fetch("S3_RESPONSE_CHECKSUM_VALIDATION", "when_supported") %>
  secret_access_key: <%= ENV["S3_SECRET_ACCESS_KEY"] %>
```

And add this to `config/environments/production.rb`:

```ruby
# Select Active Storage service via env var; default to production's S3 config.
  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym
```

Finally, lets add all the secrets to `.kamal/secrets`:
Run `bin/rails secret` copy the generated string and add it to `.kamal/secrets`

Set the SMTP_USERNAME and SMTP_PASSWORD at `./kamal_secrets`. Use the data for your current provider or
setup one using Mailgun or Sendgrid for example.

How to get each value:

- `SECRET_KEY_BASE`: Run `bin/rails secret` and copy the generated string
- `VAPID_PRIVATE_KEY`, and `VAPID_PUBLIC_KEY`: Run `bin/rails runner 'vapid_key = WebPush.generate_key; puts "VAPID_PRIVATE_KEY=#{vapid_key.private_key}"; puts "VAPID_PUBLIC_KEY=#{vapid_key.public_key}"'` and copy the generated strings
- `SMTP_USERNAME`: You should get that from your email provider. In my case I used iCloud so it was just my email.
- `SMTP_PASSWORD`: Same here, I went to iCloud settings and generated an application password.
- `SMTP_PORT`: Again, same. Although `587` is a safe bet.
- `SMTP_DOMAIN`: You guessed, same, from your provider.
- `S3_ENDPOINT`: https://fsn1.your-objectstorage.com (unless you changed the region at Hetzner)
- `S3_REGION`: fsn1
- `S3_BUCKET`: The name of the Object Storage bucket you created, like `my-fizzy-storage`
- `S3_ACCESS_KEY_ID`: Go to the Hetzner console, go to Object Storage, select yours and generate credentials.
- `S3_SECRET_ACCESS_KEY`: Same as above.

```sh
SECRET_KEY_BASE=
VAPID_PRIVATE_KEY=
VAPID_PUBLIC_KEY=
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_PORT=587
SMTP_DOMAIN=
S3_BUCKET=
S3_ENDPOINT=https://fsn1.your-objectstorage.com
S3_REGION=fsn1
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=
```

CORS

```
aws s3api get-bucket-cors --bucket fizzy-oriol-storage
{
"CORSRules": [
{
"AllowedHeaders": [
"*"
],
"AllowedMethods": [
"GET",
"PUT",
"HEAD"
],
"AllowedOrigins": [
"https://fizzy.gual.me"
]
}
]
}
```

The first time you open the website it might take a while, and then you'll see a SSL error. Just refresh and it should be OK!

Open your fizzy deploy, and sign up. You should get an email.

Run bin/kamal console, and set yourself as a staff `Identity.first.update(staff: true)`

Then you can go to https://fizzy.gual.me/admin/stats or https://fizzy.gual.me/admin/jobs

# Acknowledgments

<https://www.luizkowalski.net/production-grade-ish-deployment-on-hetzner-with-kamal/>
<https://deployn.de/en/hetzner-cloud-init/>
<https://dennmart.com/articles/get-started-with-hetzner-cloud-and-terraform-for-easy-deployments/>
https://atetux.com/how-to-create-hetzner-server-with-terraform
https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs
