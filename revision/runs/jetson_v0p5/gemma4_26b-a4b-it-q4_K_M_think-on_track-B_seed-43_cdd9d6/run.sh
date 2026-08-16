#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

REF="data/ref/chrM.fa"

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

for f1 in data/raw/*_1.fq.gz; do
    sample=$(basename "$f1" _1.fq.gz)
    f2="${f1/_1.fq.gz/_2.fq.gz}"
    
    if [[ -f "results/${sample}.bam" && -f "results/${sample}.bam.bai" ]]; then
        continue
    fi

    bwa mem -t 4 "$REF" "$f1" "$f2" | \
        samtools sort -@ 4 -o "results/${sample}.bam"
    
    samtools index "results/${sample}.bam"

    lofreq call -f "$REF" -o "results/${sample}.vcf" "results/${sample}.bam"
    bcftools view -Oz -o "results/${sample}.vcf.gz" "results/${sample}.vcf"
    tabix -p vcf "results/${sample}.vcf.gz"
    rm "results/${sample}.vcf"
done

echo -e "sample\tchrom\tpos\tref\talt\naf" > results/collapsed.tsv

for vcf in results/*.vcf.gz; do
    if [[ -f "$vcf" ]]; then
        sample_name=$(basename "$vcf" .vcf.gz)
        bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf" | \
            awk -v s="$sample_name" '{print s"\t"$0}' >> results/collapsed.tsv
    fi
done

exit 0