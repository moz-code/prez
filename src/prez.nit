# Copyright 2019 Alexandre Terrasa <alexandre@moz-code.org>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module prez

import github2
import commands
import template::macro
import ini

class Prez
	super PrezCmd
	noautoinit

	redef var name = "prez"
	redef var description = "Manage the CSGames with Github!"

	var opt_config_file = new OptionString("Chemin vers le fichiers de configuration", "--config")

	var config_file: String is lazy do
		return opt_config_file.value or else "config.ini"
	end

	redef var config = new PrezConfig(config_file) is lazy

	redef init do
		sub_commands.add new InitCmd(config)
		sub_commands.add new CreateCmd(config)
		sub_commands.add new ImportCmd(config)
	end
end

class PrezConfig
	super ConfigTree

	private fun read(key: String): String do
		assert self.has_key(key)
		return self[key].as(not null)
	end

	var api = new API(token, "prez") is lazy
	var logger = new PrezLogger

	var token_file: String  = read("config.token") is lazy
	var token: String		= token_file.to_path.read_all.trim is lazy

	var year: Int			= read("config.year").to_i is lazy
	var org_login: String	= read("config.org") is lazy
	var owner_login: String	= read("config.owner") is lazy
	var repo_name: String	= read("config.repo") is lazy

	var tpl_slug: String	= read("template.repo") is lazy
	var tpl_readme: String	= read("template.readme") is lazy

	var team_parent: String	= read("team.parent") is lazy
	var team_name: String	= read("team.name") is lazy

	var co: Map[String, User]		= load_team("co") is lazy
	var coaches: Map[String, User]	= load_team("coaches") is lazy

	var repo_slug = "{org_login}/{repo_name}" is lazy

	var owner: GitUser is lazy do
		var user = api.get_user(owner_login)
		if user == null then
			logger.error "Error: can't find owner `{owner_login}`\n"
			exit 1
		end
		return user.as(not null)
	end

	private fun load_team(config_key: String): Map[String, User] do
		var team = new HashMap[String, User]
		for role, login in at(config_key).as(not null) do
			var user = api.get_user(login)
			if user == null then
				logger.error "Can't find co member `{login}`."
			end
			team[role] = user.as(not null)
		end
		return team
	end

	fun tpl_co: Template do
		var tpl = new Template
		for role, user in co do
			var lnk_usr = "[{user.login}]({user.html_url or else "n/a"})"
			var lnk_lbl = "[{role}](https://github.com/{repo_slug}/labels/{role})"
			var coach = coaches[role]
			var lnk_coach = "[{coach.login}]({coach.html_url or else "n/a"})"
			tpl.addn "* {lnk_lbl}: {lnk_usr} (coach: {lnk_coach})"
		end
		return tpl
	end

	var monthes = [
		"Mai", "Juin", "Juillet", "Aout", "Septembre", "Octobre", "Novembre",
		"Decembre", "Janvier", "Fevrier", "Mars", "Avril"]
end

class PrezLogger
	fun error(message: String) do
		stderr.write "Error: {message}\n"
		exit 1
	end
end

abstract class PrezCmd
	super Command
	autoinit(config)

	var config: PrezConfig

	var api: API = config.api is lazy
	var logger: PrezLogger = config.logger is lazy

	fun check_error do
		var error = api.last_error
		if error == null then return
		logger.error "{error.message}\n{error.body}"
	end
end

class InitCmd
	super PrezCmd

	redef var name = "init"
	redef var description = "Init yearly management tools"

	redef fun run(args) do
		var steps = [
			# new CreateTeam(config),
			new CreateRepo(config),
			new ImportLabels(config),
			new ImportMilestones(config),
			new ImportReadme(config),
			new ImportIssues(config)
		: PrezCmd]

		for step in steps do step.run(new Array[String])
	end
end

class CreateCmd
	super PrezCmd

	redef var name = "create"
	redef var description = "Create teams, repos, projects..."

	init do
		sub_commands.add new CreateTeam(config)
		sub_commands.add new CreateRepo(config)
	end
end

class CreateTeam
	super PrezCmd

	redef var name = "team"
	redef var description = "Create the CO team"

	redef fun run(args) do
		print "Creating team {config.team_name}..."

		# Check if team exists
		var team = api.get_team(config.org_login, config.team_name)
		if team != null then
			logger.error("Team `{team.name}` already exists.")
			return
		end

		# Load parent team
		var parent = api.get_team(config.org_login, config.team_parent)
		if parent == null then
			logger.error("Parent team `{config.team_parent}` doesn't exist.")
			return
		end

		# Create CO team
		team = create_team(parent)

		# Add team members
		create_members(team)
	end

	fun create_team(parent: Team): Team do
		var post = new Team(
			name = config.team_name,
			maintainers = [config.owner_login],
			repo_names = [config.repo_slug],
			privacy = "closed",
			parent_team_id = parent.id
		)
		var team = api.post_team(config.org_login, post)
		check_error
		print "Created team {team.as(not null).name}."
		return team.as(not null)
	end

	fun create_members(team: Team) do
		for role, user in config.co do
			api.put_team_membership(team.id.as(Int), user.name.as(String), new TeamMembership)
			check_error
			print "Added team member @{user.name.as(String)} ({role})."
		end
	end
end

class CreateRepo
	super PrezCmd

	redef var name = "repo"
	redef var description = "Create the CO repository"

	redef fun run(args) do
		print "Creating repo {config.repo_slug}..."

		# Get template repository
		var template = api.get_repo(config.tpl_slug)
		if template == null then
			logger.error("Template repository `{config.tpl_slug}` not found.")
			return
		end

		# Get team
		var team = api.get_team(config.org_login, config.team_name)
		if team == null then
			logger.error("Team `{config.team_name}` not found.")
			return
		end

		create_repo(team)
		clear_labels
	end

	fun create_repo(team: Team): Repo do
		# Check if repo exists
		var repo = api.get_repo(config.repo_slug)
		if repo != null then
			logger.error("Repo `{repo.full_name}` already exists.")
			return repo
		end

		# Create new repo
		var post = new PostRepo(
			name = config.repo_name,
			description = "Suivi {team.name}",
			homepage = "http://{config.year}.csgames.org",
			is_private = true,
			has_issues = true,
			has_projects = true,
			has_wiki = true,
			auto_init = false,
			team_id = team.id
		)
		repo = api.post_repo_org(config.org_login, post)
		check_error
		print "Created repo {config.repo_slug}."
		return repo.as(not null)
	end

	fun clear_labels do
		var labels = api.get_repo_labels(config.repo_slug)
		check_error
		if labels == null then return
		for lbl in labels do
			if not (lbl.default or else false) then continue
			api.delete_label(config.repo_slug, lbl.name)
			check_error
		end
		print "Deleted default labels."
	end
end

class CreateProject
	super PrezCmd

	redef var name = "project"
	redef var description = "Create the CO project"

	redef fun run(args) do
		# TODO Create project
		# TODO columns (TODO, In Progress, Done)
	end
end

class ImportCmd
	super PrezCmd

	redef var name = "import"
	redef var description = "Import issues, labels, milestones..."

	init do
		sub_commands.add new ImportLabels(config)
		sub_commands.add new ImportMilestones(config)
		sub_commands.add new ImportIssues(config)
	end
end

class ImportLabels
	super PrezCmd

	redef var name = "labels"
	redef var description = "Import labels from project template"

	redef fun run(args) do
		print "Importing labels..."
		var labels = api.get_repo_labels(config.tpl_slug)
		check_error
		if labels == null then return
		for lbl in labels do
			var new_lbl = api.post_label(config.repo_slug, lbl)
			check_error
			print "Created label `{new_lbl.as(not null).name}`."
		end
	end
end

class ImportMilestones
	super PrezCmd

	redef var name = "milestones"
	redef var description = "Import milestones from project template"

	redef fun run(args) do
		var year = config.year - 1
		var i = 5
		for month in config.monthes do
			if i == 13 then i = 1
			if i == 1 then year += 1
			var y = if i == 12 then year + 1 else year
			var mi = if i == 12 then 1 else i + 1
			var m = if mi < 10 then "0{mi}" else mi.to_s

			var post = new Milestone(
				title = "{month} {year}",
				state = "open",
				due_on = "{y}-{m}-01T00:00:00Z"
			)
			var milestone = api.post_milestone(config.repo_slug, post)
			check_error
			print "Created milestone `{milestone.as(not null).title}`."
			i += 1
		end
	end
end

class ImportIssues
	super PrezCmd

	redef var name = "issues"
	redef var description = "Import issues from project template"

	redef fun run(args) do
		var issues = api.get_issues(config.tpl_slug)
		check_error

		var new_milestones = api.get_milestones(config.repo_slug)
		check_error

		var milestones = new HashMap[String, Milestone]
		for milestone in new_milestones.as(not null) do
			milestones[milestone.title.split(" ").first] = milestone
		end

		for issue in issues.as(not null) do
			var assignees = new Array[String]
			# Get labels names
			var labels = new Array[String]
			var issue_labels = issue.labels
			if issue_labels != null then
				for lbl in issue_labels do
					labels.add lbl.name
					if config.co.has_key(lbl.name) then
						assignees.add config.co[lbl.name].login
					end
				end
			end

			# Get milestone id
			var milestone = null
			var issue_milestone = issue.milestone
			if issue_milestone != null then
				milestone = milestones[issue_milestone.title].number
			end

			var post = new PostIssue(
				title = issue.title,
				body = issue.body,
				assignees = assignees,
				labels = labels,
				milestone = milestone
			)
			var new_issue = api.post_issue(config.repo_slug, post)
			check_error
			print "Created issue `{new_issue.as(not null).title}`."
		end
	end
end

class ImportReadme
	super PrezCmd

	redef var name = "readme"
	redef var description = "Import README from file template"

	redef fun run(args) do
		var tpl = new TemplateString.from_file(config.tpl_readme)
		tpl.replace("TEAM", config.team_name)
		tpl.replace("CO", config.tpl_co)
		var file = new FilePost(
			message = "Initialize repo",
			content = tpl.write_to_string,
			committer = config.owner
		)
		api.put_file(config.repo_slug, "README.md", file)
		# TODO check_error
		print "Created README file."
	end
end

var prez = new Prez
prez.parse(args)

# TODO Show state and progress
# prez progress
# prez issues late
# prez issues late ping
# prez reassign issues
# reimport labels, milestones, issues
