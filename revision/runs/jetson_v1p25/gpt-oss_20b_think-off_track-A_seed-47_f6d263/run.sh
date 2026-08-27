#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
    bam=results/${sample}.bam
    bai=${bam}.bai
    vcf=results/${sample}.vcf
    vcfz=${vcf}.gz

    # Alignment
    if [[ ! -f $bam || $bam -ot data/raw/${sample}_1.fq.gz || $bam -ot data/raw/${sample}_2.fq.gz ]]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
        samtools sort -@ "$THREADS" -o "$bam"
    fi

    # BAM index
    if [[ ! -f $bai || $bai -ot $bam ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Variant calling
    if [[ ! -f "${vcfz}" || "${vcfz}" -ot "$bam" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa -o "$vcf" "$bam"
    fi

    # Compress VCF
    if [[ ! -f "${vcfz}" || "${vcfz}" -ot "$vcf" ]]; then
        bgzip -c "$vcf" > "${vcfz}"
        tabix -p vcf "${vcfz}"
        rm -f "$vcf"
    fi
done

# Collapsed table
collapsed=results/collapsed.tsv
rebuild=false
for sample in "${samples[@]}"; do
    if [[ ! -f $collapsed || $collapsed -ot results/${sample}.vcf.gz ]]; then
        rebuild=true
        break
    fi
done

if $rebuild; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for sample in "${samples[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$collapsed"
    done
fi

exit 0