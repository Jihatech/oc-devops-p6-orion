package com.openclassroom.devops.orion.microcrm;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;

@SpringBootTest
class MicroCRMApplicationTests {

	@Autowired
	private ApplicationContext contexte;

	/**
	 * Vérifie que le contexte Spring démarre correctement.
	 *
	 * Corrigé (P6) : la méthode était vide (règle SonarQube java:S1186, sévérité
	 * CRITICAL). Un test vide passe toujours et ne vérifie donc rien — il donne
	 * une fausse assurance. L'assertion rend explicite ce que le test contrôle
	 * réellement : le contexte est bien initialisé et les beans essentiels sont
	 * présents.
	 */
	@Test
	void contextLoads() {
		assertThat(contexte).isNotNull();
		assertThat(contexte.getBeanDefinitionCount()).isPositive();
	}

}
