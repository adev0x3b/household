# Admin

[Documentation](../README.md) › [Guide](README.md)

The admin runs the copy: its households, its settings, the assistant's model, the assistant's languages, and the app's own health. The first account made on the setup page is the admin. The admin's pages are under **Admin** in the navigation, and none of them shows a household's records.

Anything the admin does to someone else's account, and every save of the settings, asks for the admin's password again, which then holds for a while.

<img src="images/admin-settings-desktop.png" width="800" alt="The admin's Settings page on a desktop: what the installation allows, the Bookshelf key and lookups, the deploy token, the demo password, and the password asked again before saving">

## Households

Every person belongs to one household, and **Households** lists them with their members and the invitations waiting. **New household** asks its name and its first member's email: that person gets a link to join, shown once to hand over, becomes the household's owner and invites the others.

From a household's page the admin can also make a link for a member to set a new password, or remove a person.

## Settings

**Settings** holds what the whole copy uses, the same for every household, in the sections the setup page asked:

- **What this installation allows**: the assistant, Files and the storage per household, photos in messages, members inviting people, push notifications, looking for new versions, the assistant messages per household per day, the people per household and the invitations per member. Turning something off hides it; nothing anyone kept is deleted.
- **Bookshelf**: the Google Books key and the book lookups per household per day.
- **Deployment**: the GitHub token behind the Deployment page's buttons, on a copy that runs the pipeline.
- **Demo household**: the password of the demo accounts, where the copy runs a demo.

Every value here can be changed here. Where the copy's environment names one, that is only where it started, before anything was saved.

## Assistant settings

**Assistant settings** picks who answers the assistant: an Ollama server by its address, or Anthropic or OpenAI by an API key, which is stored encrypted and never shown again. **Test connection** checks the key and lists the provider's models before saving; then the model's name, its context window, and under Advanced the temperature, thinking and the longest reply. A saved change applies to every household from the next reply on. The page also shows what each household asked this month, with the tokens read and written and the cost where the provider has prices.

<img src="images/assistant-settings-desktop.png" width="800" alt="The assistant settings on a desktop: the provider in use and whether it answers, usage this month, the provider choice, the connection, the model, and Advanced">

## Languages

**Languages** is the dictionaries the assistant uses to understand the names of supplies and things in each language. Each language's words come from Wiktionary; an import runs in the background, is held for the admin's review when its cases need confirming, and is used only after its checks pass. The admin is told on the bell how each import ended.

## Errors and jobs

**Errors** lists every error the app reported, grouped by kind, with where it happened; **Jobs** is the background work: what is queued, running, finished or failed, and a failed job can be retried or discarded there. The admin is told on the bell, and by push, the first time a kind of error appears and when a job fails for good, at most once an hour for the same thing. An error only the admin can fix says what to fix.

## Evals

**Evals** runs the assistant's test scenarios against the model in use and keeps each run: how many passed, how long and how many tokens a scenario took, and which scenarios fail most.

## Deployment

**Deployment** says what this copy runs: its version, environment, when it booted, and whether its database and job worker answer. On a self-hosted copy it also checks once a day whether a newer release is out and shows the command to update. On a copy that runs the pipeline it also shows dev, staging, the demo and production, and previews a branch, deploys, promotes a release to production, rolls back and freezes deploys.

---

How it works: [Tenancy](../architecture/tenancy.md), [Delivery](../architecture/delivery.md)

[← People](people.md)
