pipelineJob('hello-from-jenkinsfile') {
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/ibugithub/jenkins-demo.git') 
                    }
                    branches('main')
                }
                scriptPath('Jenkinsfile')
            }
        }
    }
}
